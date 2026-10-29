// End-to-end tests against a real Pusher-compatible server, such as a local
// pusher-server. Skipped unless HIBIRA_E2E_KEY is set:
//
//   HIBIRA_E2E_HOST=127.0.0.1 HIBIRA_E2E_PORT=8080 HIBIRA_E2E_TLS=false \
//   HIBIRA_E2E_APP_ID=app1 HIBIRA_E2E_KEY=key1 HIBIRA_E2E_SECRET=... \
//   dart test test/e2e_test.dart
//
// The app needs client events turned on. The test signs subscriptions with
// the secret itself, as your backend would.
@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:hibira/hibira.dart';
import 'package:http/http.dart' as http;
import 'package:pinenacl/x25519.dart' show SecretBox, Uint8List;
import 'package:test/test.dart';

final env = Platform.environment;
final host = env['HIBIRA_E2E_HOST'] ?? '127.0.0.1';
final port = int.parse(env['HIBIRA_E2E_PORT'] ?? '8080');
final tls = env['HIBIRA_E2E_TLS'] == 'true';
final appId = env['HIBIRA_E2E_APP_ID'] ?? '';
final key = env['HIBIRA_E2E_KEY'] ?? '';
final secret = env['HIBIRA_E2E_SECRET'] ?? '';
final sharedSecret = base64Encode(
  List<int>.generate(32, (_) => Random.secure().nextInt(256)),
);

String sign(String text) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(text)).toString();

Future<HibiraAuth> authorize(
  String socketId,
  String channel, [
  String? user,
]) async {
  final channelData = user == null
      ? null
      : jsonEncode({
          'user_id': user,
          'user_info': {'name': 'User $user'},
        });
  final signed = [socketId, channel, ?channelData].join(':');
  return HibiraAuth(
    auth: '$key:${sign(signed)}',
    channelData: channelData,
    sharedSecret: channel.startsWith('private-encrypted-')
        ? sharedSecret
        : null,
  );
}

HibiraClient newClient({String? user}) => HibiraClient(
  key,
  options: HibiraOptions(
    host: host,
    port: port,
    useTLS: tls,
    authorizer: (socketId, channel) => authorize(socketId, channel, user),
    userAuthenticator: (socketId) async {
      final userData = jsonEncode({'id': user ?? 'anon'});
      return HibiraUserAuth(
        auth: '$key:${sign('$socketId::user::$userData')}',
        userData: userData,
      );
    },
  ),
);

/// Triggers an event through the HTTP API, as a server SDK would.
Future<void> publish(String channel, String event, Object? data) async {
  final body = jsonEncode({
    'name': event,
    'channels': [channel],
    'data': data is String ? data : jsonEncode(data),
  });
  final path = '/apps/$appId/events';
  final query = {
    'auth_key': key,
    'auth_timestamp': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
    'auth_version': '1.0',
    'body_md5': md5.convert(utf8.encode(body)).toString(),
  };
  final sorted = (query.keys.toList()..sort())
      .map((k) => '$k=${query[k]}')
      .join('&');
  query['auth_signature'] = sign('POST\n$path\n$sorted');
  final uri = Uri(
    scheme: tls ? 'https' : 'http',
    host: host,
    port: port,
    path: path,
    queryParameters: query,
  );
  final res = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: body,
  );
  if (res.statusCode != 200) {
    throw StateError('publish failed: ${res.statusCode} ${res.body}');
  }
}

String unique(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

void main() {
  final skip = key.isEmpty ? 'set HIBIRA_E2E_KEY to run' : null;
  final clients = <HibiraClient>[];

  Future<HibiraClient> connected({String? user}) async {
    final c = newClient(user: user);
    clients.add(c);
    await c.connect().timeout(const Duration(seconds: 10));
    return c;
  }

  tearDown(() async {
    for (final c in clients) {
      await c.dispose();
    }
    clients.clear();
  });

  group('e2e', skip: skip, () {
    test('connects and gets a socket id', () async {
      final c = await connected();
      expect(c.state, HibiraConnectionState.connected);
      expect(c.socketId, matches(RegExp(r'^\d+\.\d+$')));
    });

    test('public channel receives server events', () async {
      final c = await connected();
      final ch = c.subscribe(unique('orders'));
      await ch.whenSubscribed.timeout(const Duration(seconds: 5));
      final got = ch.on('shipped').first;
      await publish(ch.name, 'shipped', {'id': 7});
      expect((await got.timeout(const Duration(seconds: 5))).data, {'id': 7});
    });

    test('private channel and client events', () async {
      final a = await connected(), b = await connected();
      final name = unique('private-game');
      final chA = a.subscribe(name), chB = b.subscribe(name);
      await Future.wait([chA.whenSubscribed, chB.whenSubscribed]);
      final got = chB.on('client-move').first;
      expect(chA.trigger('client-move', {'x': 3}), isTrue);
      expect((await got.timeout(const Duration(seconds: 5))).data, {'x': 3});
    });

    test('a bad signature is refused', () async {
      final c = HibiraClient(
        key,
        options: HibiraOptions(
          host: host,
          port: port,
          useTLS: tls,
          authorizer: (_, _) async => HibiraAuth(auth: '$key:${'0' * 64}'),
        ),
      );
      clients.add(c);
      await c.connect();
      final ch = c.subscribe(unique('private-x'));
      await expectLater(
        ch.whenSubscribed.timeout(const Duration(seconds: 5)),
        throwsA(isA<HibiraException>()),
      );
      expect(ch.isSubscribed, isFalse);
    });

    test('presence members and stamped user ids', () async {
      final a = await connected(user: 'ann');
      final name = unique('presence-room');
      final roomA = a.subscribePresence(name);
      await roomA.whenSubscribed;
      expect(roomA.members.keys, ['ann']);
      expect(roomA.me!.info, {'name': 'User ann'});

      final joined = roomA.memberAdded.first;
      final b = await connected(user: 'bo');
      final roomB = b.subscribePresence(name);
      await roomB.whenSubscribed;
      expect((await joined.timeout(const Duration(seconds: 5))).id, 'bo');
      expect(roomB.members.keys, unorderedEquals(['ann', 'bo']));

      final move = roomA.on('client-move').first;
      roomB.trigger('client-move', {'x': 1});
      expect((await move.timeout(const Duration(seconds: 5))).userId, 'bo');

      final left = roomA.memberRemoved.first;
      await b.disconnect();
      expect((await left.timeout(const Duration(seconds: 10))).id, 'bo');
      expect(roomA.count, 1);
    });

    test('encrypted channel decrypts', () async {
      final c = await connected();
      final ch = c.subscribe(unique('private-encrypted-vault'));
      await ch.whenSubscribed;
      final box = SecretBox(Uint8List.fromList(base64Decode(sharedSecret)));
      final sealed = box.encrypt(
        Uint8List.fromList(utf8.encode('{"pin":"42"}')),
      );
      final got = ch.on('secret').first;
      await publish(ch.name, 'secret', {
        'nonce': base64Encode(sealed.nonce),
        'ciphertext': base64Encode(sealed.cipherText),
      });
      expect((await got.timeout(const Duration(seconds: 5))).data, {
        'pin': '42',
      });
    });

    test('sign in and receive events sent to the user', () async {
      final c = await connected(
        user: 'u-${DateTime.now().microsecondsSinceEpoch}',
      );
      await c.signIn().timeout(const Duration(seconds: 5));
      expect(c.user.id, startsWith('u-'));
      // The server-to-user subscription is sent right after signin_success.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final got = c.user.on('notice').first;
      await publish('#server-to-user-${c.user.id}', 'notice', {'text': 'hi'});
      expect((await got.timeout(const Duration(seconds: 5))).data, {
        'text': 'hi',
      });
    });

    test('resubscribes after the connection drops', () async {
      final c = await connected();
      final ch = c.subscribe(unique('orders'));
      await ch.whenSubscribed;
      final back = c.stateChanges.firstWhere(
        (s) => s == HibiraConnectionState.connected,
      );
      // Drop the socket from our side without telling the client.
      await c.disconnect();
      unawaited(c.connect());
      await back.timeout(const Duration(seconds: 10));
      await ch.whenSubscribed.timeout(const Duration(seconds: 5));
      final got = ch.on('again').first;
      await publish(ch.name, 'again', 'ok');
      expect((await got.timeout(const Duration(seconds: 5))).data, 'ok');
    });
  });
}
