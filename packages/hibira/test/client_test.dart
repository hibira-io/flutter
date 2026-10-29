import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:hibira/hibira.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pinenacl/x25519.dart' show SecretBox, Uint8List;
import 'package:test/test.dart';

import 'fake_socket.dart';

void main() {
  late FakeServer server;

  setUp(() => server = FakeServer());

  HibiraClient client({
    HibiraAuthorizer? authorizer,
    Uri? authEndpoint,
    http.Client? httpClient,
    HibiraUserAuthenticator? userAuthenticator,
    bool autoReconnect = true,
  }) => HibiraClient(
    'app-key',
    options: HibiraOptions(
      connector: server.connect,
      authorizer: authorizer,
      authEndpoint: authEndpoint,
      httpClient: httpClient,
      userAuthenticator: userAuthenticator,
      autoReconnect: autoReconnect,
    ),
  );

  group('connection', () {
    test('builds the Pusher URL and connects', () async {
      final c = client();
      final states = <HibiraConnectionState>[];
      c.stateChanges.listen(states.add);
      final done = c.connect();
      await pump();
      final uri = server.last.uri;
      expect(uri.scheme, 'wss');
      expect(uri.host, 'ws.hibira.io');
      expect(uri.port, 443);
      expect(uri.path, '/app/app-key');
      expect(uri.queryParameters['protocol'], '7');
      expect(uri.queryParameters['client'], 'dart');
      server.last.establish('1.2');
      await done;
      expect(c.state, HibiraConnectionState.connected);
      expect(c.socketId, '1.2');
      expect(states, [
        HibiraConnectionState.connecting,
        HibiraConnectionState.connected,
      ]);
      await c.dispose();
    });

    test('answers pings', () async {
      final c = client();
      final done = c.connect();
      await pump();
      server.last.establish();
      await done;
      server.last.push('pusher:ping');
      await pump();
      expect(server.last.sentEvents('pusher:pong'), hasLength(1));
      await c.dispose();
    });

    test('fails connect and stops on 4000-4099 close codes', () async {
      final c = client();
      final errors = <HibiraException>[];
      c.errors.listen(errors.add);
      final done = c.connect();
      await pump();
      server.last.push(
        'pusher:error',
        data: {'code': 4001, 'message': 'App key not found'},
      );
      server.last.serverClose(4001, 'App key not found');
      await expectLater(
        done,
        throwsA(isA<HibiraException>().having((e) => e.code, 'code', 4001)),
      );
      expect(c.state, HibiraConnectionState.disconnected);
      expect(errors.single.code, 4001);
      expect(server.sockets, hasLength(1));
      await c.dispose();
    });

    test('reconnects with backoff and resubscribes', () {
      fakeAsync((async) {
        final c = client();
        c.connect();
        async.flushMicrotasks();
        server.last.establish('1.1');
        async.flushMicrotasks();
        c.subscribe('orders');
        async.flushMicrotasks();
        expect(server.last.sentEvents('pusher:subscribe'), hasLength(1));

        server.last.serverClose(1006);
        async.flushMicrotasks();
        expect(c.state, HibiraConnectionState.reconnecting);
        expect(c.channel('orders')!.isSubscribed, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(server.sockets, hasLength(2));
        server.last.establish('2.2');
        async.flushMicrotasks();
        expect(c.state, HibiraConnectionState.connected);
        expect(server.last.sentEvents('pusher:subscribe').single['data'], {
          'channel': 'orders',
        });
        c.dispose();
        async.flushMicrotasks();
      });
    });

    test('reconnects right away on 4200-4299', () {
      fakeAsync((async) {
        final c = client();
        c.connect();
        async.flushMicrotasks();
        server.last.establish();
        async.flushMicrotasks();
        server.last.serverClose(4200, 'reconnect');
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        expect(server.sockets, hasLength(2));
        c.dispose();
        async.flushMicrotasks();
      });
    });

    test('pings when idle and reconnects without a pong', () {
      fakeAsync((async) {
        final c = client();
        c.connect();
        async.flushMicrotasks();
        server.last.establish('1.1', 10); // server activity_timeout wins
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(server.last.sentEvents('pusher:ping'), hasLength(1));
        async.elapse(const Duration(seconds: 30));
        expect(server.sockets.first.isClosed, isTrue);
        expect(server.sockets.first.closeCode, 4201);
        async.elapse(const Duration(seconds: 1));
        expect(server.sockets, hasLength(2));
        c.dispose();
        async.flushMicrotasks();
      });
    });

    test('a reply resets the ping timer', () {
      fakeAsync((async) {
        final c = client();
        c.connect();
        async.flushMicrotasks();
        server.last.establish('1.1', 10);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        server.last.push('pusher:pong');
        async.flushMicrotasks();
        // Pinged again 10 s after the pong, still waiting for the reply.
        async.elapse(const Duration(seconds: 35));
        expect(server.sockets, hasLength(1));
        expect(server.last.sentEvents('pusher:ping'), hasLength(2));
        c.dispose();
        async.flushMicrotasks();
      });
    });

    test('disconnect stops reconnecting', () async {
      final c = client();
      final done = c.connect();
      await pump();
      server.last.establish();
      await done;
      await c.disconnect();
      await pump();
      expect(c.state, HibiraConnectionState.disconnected);
      expect(server.last.closeCode, 1000);
      expect(server.sockets, hasLength(1));
      await c.dispose();
    });
  });

  group('channels', () {
    Future<HibiraClient> connected({
      HibiraAuthorizer? authorizer,
      Uri? authEndpoint,
      http.Client? httpClient,
    }) async {
      final c = client(
        authorizer: authorizer,
        authEndpoint: authEndpoint,
        httpClient: httpClient,
      );
      final done = c.connect();
      await pump();
      server.last.establish('9.9');
      await done;
      return c;
    }

    test('public channel events and decoded data', () async {
      final c = await connected();
      final ch = c.subscribe('orders');
      expect(c.subscribe('orders'), same(ch));
      await pump();
      expect(server.last.sent.last, {
        'event': 'pusher:subscribe',
        'data': {'channel': 'orders'},
      });
      final got = <HibiraEvent>[];
      final global = <HibiraEvent>[];
      ch.bind('shipped', got.add);
      c.events.listen(global.add);
      server.last.push(
        'pusher_internal:subscription_succeeded',
        channel: 'orders',
      );
      await ch.whenSubscribed;
      expect(ch.isSubscribed, isTrue);
      server.last.push('shipped', channel: 'orders', data: {'id': 7});
      server.last.push('shipped', channel: 'orders', data: 'plain text');
      await pump();
      expect(got.map((e) => e.data), [
        {'id': 7},
        'plain text',
      ]);
      expect(global.map((e) => e.name), [
        'pusher:subscription_succeeded',
        'shipped',
        'shipped',
      ]);
      await c.dispose();
    });

    test('private channel signs with the auth endpoint', () async {
      late http.Request request;
      final mock = MockClient((req) async {
        request = req;
        return http.Response(jsonEncode({'auth': 'app-key:sig'}), 200);
      });
      final c = await connected(
        authEndpoint: Uri.parse('https://example.com/auth'),
        httpClient: mock,
      );
      c.subscribe('private-user-1');
      await pump();
      await pump();
      expect(request.method, 'POST');
      expect(request.bodyFields, {
        'socket_id': '9.9',
        'channel_name': 'private-user-1',
      });
      expect(server.last.sent.last, {
        'event': 'pusher:subscribe',
        'data': {'channel': 'private-user-1', 'auth': 'app-key:sig'},
      });
      await c.dispose();
    });

    test('a refused subscription reports the status', () async {
      final mock = MockClient(
        (_) async => http.Response('{"error":"room full"}', 403),
      );
      final c = await connected(
        authEndpoint: Uri.parse('https://example.com/auth'),
        httpClient: mock,
      );
      final ch = c.subscribe('presence-room');
      await expectLater(
        ch.whenSubscribed,
        throwsA(
          isA<HibiraException>()
              .having((e) => e.status, 'status', 403)
              .having((e) => e.message, 'message', 'room full'),
        ),
      );
      expect(server.last.sentEvents('pusher:subscribe'), isEmpty);
      await c.dispose();
    });

    test('presence members', () async {
      final c = await connected(
        authorizer: (socketId, name) async => const HibiraAuth(
          auth: 'app-key:sig',
          channelData: '{"user_id":"u1","user_info":{"name":"Ann"}}',
        ),
      );
      final room = c.subscribePresence('presence-room');
      await pump();
      expect(
        (server.last.sent.last['data'] as Map)['channel_data'],
        '{"user_id":"u1","user_info":{"name":"Ann"}}',
      );
      final added = <HibiraMember>[], removed = <HibiraMember>[];
      room.memberAdded.listen(added.add);
      room.memberRemoved.listen(removed.add);
      server.last.push(
        'pusher_internal:subscription_succeeded',
        channel: 'presence-room',
        data: {
          'presence': {
            'ids': ['u1', 'u2'],
            'hash': {
              'u1': {'name': 'Ann'},
              'u2': {'name': 'Bo'},
            },
            'count': 2,
          },
        },
      );
      await room.whenSubscribed;
      expect(room.count, 2);
      expect(room.myId, 'u1');
      expect(room.me!.info, {'name': 'Ann'});
      server.last.push(
        'pusher_internal:member_added',
        channel: 'presence-room',
        data: {
          'user_id': 'u3',
          'user_info': {'name': 'Cy'},
        },
      );
      server.last.push(
        'pusher_internal:member_removed',
        channel: 'presence-room',
        data: {'user_id': 'u2'},
      );
      server.last.push(
        'client-move',
        channel: 'presence-room',
        data: {'x': 1},
        userId: 'u3',
      );
      final move = await room.on('client-move').first;
      expect(added.single.id, 'u3');
      expect(removed.single.info, {'name': 'Bo'});
      expect(room.members.keys, unorderedEquals(['u1', 'u3']));
      expect(move.userId, 'u3');
      await c.dispose();
    });

    test('client events', () async {
      final c = await connected(
        authorizer: (_, _) async => const HibiraAuth(auth: 'k:s'),
      );
      final ch = c.subscribe('private-game');
      await pump();
      expect(ch.trigger('client-move', {'x': 1}), isFalse);
      server.last.push(
        'pusher_internal:subscription_succeeded',
        channel: 'private-game',
      );
      await ch.whenSubscribed;
      expect(ch.trigger('client-move', {'x': 1}), isTrue);
      expect(server.last.sent.last, {
        'event': 'client-move',
        'channel': 'private-game',
        'data': {'x': 1},
      });
      expect(() => c.trigger('orders', 'client-x', 1), throwsArgumentError);
      expect(() => ch.trigger('move', 1), throwsArgumentError);
      await c.dispose();
    });

    test('unsubscribe', () async {
      final c = await connected();
      final ch = c.subscribe('orders');
      await pump();
      server.last.push(
        'pusher_internal:subscription_succeeded',
        channel: 'orders',
      );
      await ch.whenSubscribed;
      ch.unsubscribe();
      expect(c.channel('orders'), isNull);
      expect(server.last.sent.last, {
        'event': 'pusher:unsubscribe',
        'data': {'channel': 'orders'},
      });
      await c.dispose();
    });

    test('encrypted channel decrypts events', () async {
      final key = List<int>.generate(32, (i) => i);
      final c = await connected(
        authorizer: (_, _) async =>
            HibiraAuth(auth: 'k:s', sharedSecret: base64Encode(key)),
      );
      final ch = c.subscribe('private-encrypted-secrets');
      await pump();
      final box = SecretBox(Uint8List.fromList(key));
      final sealed = box.encrypt(
        Uint8List.fromList(utf8.encode('{"pin":"1234"}')),
      );
      server.last.push(
        'secret',
        channel: 'private-encrypted-secrets',
        data: {
          'nonce': base64Encode(sealed.nonce),
          'ciphertext': base64Encode(sealed.cipherText),
        },
      );
      final e = await ch.on('secret').first;
      expect(e.data, {'pin': '1234'});
      await c.dispose();
    });

    test('encrypted channel reports undecryptable events', () async {
      var calls = 0;
      final c = await connected(
        authorizer: (_, _) async {
          calls++;
          return HibiraAuth(
            auth: 'k:s',
            sharedSecret: base64Encode(List.filled(32, 1)),
          );
        },
      );
      final ch = c.subscribe('private-encrypted-secrets');
      await pump();
      final error = ch.errors.first;
      server.last.push(
        'secret',
        channel: 'private-encrypted-secrets',
        data: {
          'nonce': base64Encode(List.filled(24, 0)),
          'ciphertext': base64Encode(List.filled(40, 0)),
        },
      );
      expect((await error).message, contains('could not decrypt'));
      expect(calls, 2); // signed again once for a fresh key
      await c.dispose();
    });
  });

  group('user', () {
    test('signs in and receives server-to-user events', () async {
      final c = client(
        userAuthenticator: (socketId) async =>
            const HibiraUserAuth(auth: 'k:s', userData: '{"id":"u1"}'),
      );
      final done = c.connect();
      await pump();
      server.last.establish();
      await done;
      final signedIn = c.signIn();
      await pump();
      expect(server.last.sent.last, {
        'event': 'pusher:signin',
        'data': {'auth': 'k:s', 'user_data': '{"id":"u1"}'},
      });
      server.last.push(
        'pusher:signin_success',
        data: {'user_data': '{"id":"u1"}'},
      );
      await signedIn;
      expect(c.user.id, 'u1');
      expect(server.last.sent.last, {
        'event': 'pusher:subscribe',
        'data': {'channel': '#server-to-user-u1'},
      });
      server.last.push(
        'notice',
        channel: '#server-to-user-u1',
        data: {'text': 'hi'},
      );
      final e = await c.user.on('notice').first;
      expect(e.data, {'text': 'hi'});
      await c.dispose();
    });
  });
}
