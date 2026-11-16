import 'dart:convert';

import 'package:hibira_chat/hibira_chat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

String jwt(String sub, {int? exp}) {
  String b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');
  final e = exp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  return '${b64('{"alg":"HS256"}')}.${b64('{"sub":"$sub","exp":$e}')}.sig';
}

String msg(int seq, {String sender = 'bob', String? text}) => jsonEncode({
  'id': 'id$seq',
  'seq': seq,
  'sender': sender,
  'kind': 'text',
  'text': text ?? 'm$seq',
  'created_at': 't$seq',
});

String list(Iterable<int> seqs, {int last = 120}) =>
    '{"messages":[${seqs.map(msg).join(',')}],"last_seq":$last}';

void main() {
  test('reads the user from the token', () {
    expect(ChatClient.tokenUser(jwt('ann')), 'ann');
    expect(ChatClient.tokenUser('nope'), '');
  });

  test('sends to the user routes', () async {
    late http.Request seen;
    final client = ChatClient(
      appId: 'app-1',
      token: () async => jwt('ann'),
      host: 'https://chat.test',
      httpClient: MockClient((req) async {
        seen = req;
        return http.Response(
          '{"message":{"id":"m1","seq":4,"sender":"ann","text":"hi","language":"en",'
          '"translations":{"ja":"こんにちは"},"reactions":{"👍":["bob"]}},"push":{"users":1}}',
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final res = await client.send('trip 1', 'hi', metadata: {'reply_to': 2});
    expect(res.message.seq, 4);
    expect(res.message.reactions['👍'], ['bob']);
    expect(res.message.textFor('ja'), 'こんにちは');
    expect(res.message.textFor('ko'), 'hi');
    expect(res.pushedUsers, 1);
    expect(seen.method, 'POST');
    expect(
      seen.url.path,
      '/apps/app-1/chat/me/conversations/trip%201/messages',
    );
    expect(seen.headers['Authorization'], startsWith('Bearer ey'));
    expect(jsonDecode(seen.body), {
      'text': 'hi',
      'metadata': {'reply_to': 2},
    });
    expect(client.userId, 'ann');
  });

  test('fetches a new token after a 401, and throws API errors', () async {
    var tokens = 0;
    var calls = 0;
    final client = ChatClient(
      appId: 'a',
      token: () async {
        tokens++;
        return jwt('ann');
      },
      host: 'https://chat.test',
      httpClient: MockClient((req) async {
        calls++;
        if (calls == 1) return http.Response('{"error":"expired"}', 401);
        if (req.url.path.endsWith('/typing')) {
          return http.Response('{"error":"you are muted"}', 403);
        }
        return http.Response(list([1], last: 1), 200);
      }),
    );
    final page = await client.messages('c', last: 10);
    expect(page.messages.single.seq, 1);
    expect(tokens, 2);
    await expectLater(
      client.typing('c'),
      throwsA(
        isA<ChatException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.message, 'message', 'you are muted'),
      ),
    );
  });

  test('sets the language and translates on request', () async {
    final seen = <String>[];
    final client = ChatClient(
      appId: 'a',
      token: () async => jwt('ann'),
      host: 'https://chat.test',
      httpClient: MockClient((req) async {
        seen.add('${req.method} ${req.url.path} ${req.body}');
        if (req.url.path.endsWith('/translations')) {
          return http.Response.bytes(
            utf8.encode(
              '{"message":{"seq":3,"text":"hi","translations":{"ja":"やあ"}}}',
            ),
            200,
          );
        }
        return http.Response('{"user_id":"ann","language":"ja"}', 200);
      }),
    );
    expect(await client.setLanguage('ja'), 'ja');
    final m = await client.translate('c', 3, 'ja');
    expect(m.textFor('ja'), 'やあ');
    expect(seen, [
      'PUT /apps/a/chat/me/ {"language":"ja"}',
      'POST /apps/a/chat/me/conversations/c/messages/3/translations {"language":"ja"}',
    ]);
  });

  test('parses events', () async {
    final client = ChatClient(
      appId: 'a',
      token: () async => jwt('ann'),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    final got = client.events.first;
    expect(
      client.handleEvent(
        'chat.read',
        '{"conversation_id":"c","user_id":"bob","read_seq":7}',
      ),
      isTrue,
    );
    final e = await got as ChatRead;
    expect([e.conversationId, e.userId, e.readSeq], ['c', 'bob', 7]);
    expect(client.handleEvent('other', '{}'), isFalse);
    expect(client.handleEvent('chat.left', '{}'), isFalse);
  });

  test('a conversation pages, applies events and catches up', () async {
    final paths = <String>[];
    final client = ChatClient(
      appId: 'a',
      token: () async => jwt('ann'),
      host: 'https://chat.test',
      httpClient: MockClient((req) async {
        final p =
            req.url.path.replaceFirst('/apps/a/chat/me', '') +
            (req.url.hasQuery ? '?${req.url.query}' : '');
        paths.add('${req.method} $p');
        switch (p) {
          case '/conversations/c':
            return http.Response(
              '{"conversation":{"id":"c","members":[{"user_id":"ann","read_seq":3},{"user_id":"bob","read_seq":5}],"last_seq":120}}',
              200,
            );
          case '/conversations/c/messages?last=50':
            return http.Response(
              list([for (var i = 71; i <= 120; i++) i]),
              200,
            );
          case '/conversations/c/messages?after=20&limit=50':
            return http.Response(list([for (var i = 21; i <= 70; i++) i]), 200);
          case '/conversations/c/messages?after=0&limit=20':
            return http.Response(list([for (var i = 1; i <= 20; i++) i]), 200);
          case '/conversations/c/read':
            return http.Response('{"read_seq":121}', 200);
          case '/conversations/c/messages' when req.method == 'POST':
            return http.Response(
              '{"message":${msg(122, sender: 'ann', text: 'hello')}}',
              201,
            );
        }
        if (p.startsWith('/conversations/c/messages?after=121')) {
          return http.Response(list([121], last: 121), 200);
        }
        if (p.startsWith('/conversations/c/messages?last=')) {
          return http.Response(
            '{"messages":[${msg(120, text: 'edited')},${msg(121)}],"last_seq":121}',
            200,
          );
        }
        return http.Response('{"error":"not found"}', 404);
      }),
    );
    final c = client.conversationView('c');
    await c.refresh();
    expect(c.state.messages.length, 50);
    expect(c.state.hasOlder, isTrue);
    expect(c.state.reads['bob'], 5);

    await c.loadOlder();
    await c.loadOlder();
    expect(c.state.messages.map((m) => m.seq), [
      for (var i = 1; i <= 120; i++) i,
    ]);
    expect(c.state.hasOlder, isFalse);

    c.start();
    await c.refresh();
    client.handleEvent(
      'chat.typing',
      '{"conversation_id":"c","user_id":"bob","typing":true}',
    );
    expect(c.state.typing, {'bob'});
    client.handleEvent(
      'chat.message',
      '{"conversation_id":"c","message":${msg(121)}}',
    );
    expect(c.state.lastSeq, 121);
    expect(c.state.typing, isEmpty);
    client.handleEvent(
      'chat.message',
      '{"conversation_id":"x","message":${msg(500)}}',
    );
    expect(c.state.lastSeq, 121);
    client.handleEvent(
      'chat.read',
      '{"conversation_id":"c","user_id":"bob","read_seq":121}',
    );
    expect(c.state.readBy(121, 'ann'), ['bob']);

    client.notifyLive();
    await c.refresh();
    expect(c.state.messages.firstWhere((m) => m.seq == 120).text, 'edited');
    expect(
      paths.any((p) => p.startsWith('GET /conversations/c/messages?after=121')),
      isTrue,
    );

    await c.markRead();
    expect(c.state.reads['ann'], 121);
    final sent = await c.send('hello');
    expect(sent.seq, 122);
    expect(c.state.lastSeq, 122);

    client.handleEvent('chat.left', '{"conversation_id":"c"}');
    expect(c.state.closed, isTrue);
    c.dispose();
  });

  test('the list moves conversations and counts unread', () async {
    final client = ChatClient(
      appId: 'a',
      token: () async => jwt('ann'),
      httpClient: MockClient(
        (_) async => http.Response(
          '{"conversations":[{"id":"a","last_seq":3,"unread":0},{"id":"b","last_seq":9,"unread":2}],"next":""}',
          200,
        ),
      ),
    );
    await client.currentUser();
    final l = client.conversationList();
    await l.refresh();
    l.start();
    expect(l.state.conversations.map((c) => c.id), ['a', 'b']);
    client.handleEvent(
      'chat.message',
      '{"conversation_id":"b","message":${msg(10)}}',
    );
    expect(l.state.conversations.map((c) => c.id), ['b', 'a']);
    expect(l.state.unread, 3);
    client.handleEvent(
      'chat.read',
      '{"conversation_id":"b","user_id":"ann","read_seq":10}',
    );
    expect(l.state.unread, 0);
    client.handleEvent('chat.deleted', '{"conversation_id":"a"}');
    expect(l.state.conversations.map((c) => c.id), ['b']);
    l.dispose();
  });
}
