import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hibira_inbox/hibira_inbox.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake inbox API: the user's notifications, newest first.
class FakeApi {
  FakeApi(int count) {
    for (var i = count; i >= 1; i--) {
      items.add({
        'id': 'ntf_${i.toString().padLeft(3, '0')}',
        'title': 'Order $i shipped',
        'body': 'It should arrive on Tuesday.',
        'category': 'orders',
        'created_at': DateTime.now()
            .subtract(Duration(minutes: i))
            .toUtc()
            .toIso8601String(),
        'read_at': null,
        'archived_at': null,
      });
    }
  }

  final items = <Map<String, Object?>>[];
  final requests = <http.Request>[];
  int tokens = 0;
  bool fail = false;

  int get unread => items
      .where((n) => n['read_at'] == null && n['archived_at'] == null)
      .length;

  bool _matches(Map<String, Object?> n, String status) => switch (status) {
    'unread' => n['read_at'] == null && n['archived_at'] == null,
    'archived' => n['archived_at'] != null,
    'all' => true,
    _ => n['archived_at'] == null,
  };

  late final client = MockClient((req) async {
    requests.add(req);
    if (req.headers['Authorization'] != 'Bearer tok-$tokens') {
      return http.Response('{"error":"invalid token"}', 401);
    }
    if (fail) return http.Response('{"error":"boom"}', 500);
    if (req.method == 'GET') {
      final q = req.url.queryParameters;
      final limit = int.parse(q['limit'] ?? '20');
      var list = items.where((n) => _matches(n, q['status'] ?? ''));
      final before = q['before'];
      if (before != null) {
        list = list.where((n) => (n['id'] as String).compareTo(before) < 0);
      }
      final page = list.take(limit).toList();
      final more = list.length > limit;
      return http.Response(
        jsonEncode({
          'notifications': page,
          'next': more ? page.last['id'] : '',
          'unread': unread,
        }),
        200,
      );
    }
    final body = jsonDecode(req.body) as Map;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final n in items) {
      if (body['all'] != true && !(body['ids'] as List).contains(n['id'])) {
        continue;
      }
      if (body['read'] != null) {
        n['read_at'] = body['read'] == true ? now : null;
      }
      if (body['archived'] != null) {
        n['archived_at'] = body['archived'] == true ? now : null;
      }
    }
    return http.Response(jsonEncode({'unread': unread}), 200);
  });

  HibiraInbox inbox({int pageSize = 20}) => HibiraInbox(
    appId: 'app1',
    token: () async => 'tok-${++tokens}',
    host: 'http://api.test',
    pageSize: pageSize,
    pollInterval: Duration.zero,
    httpClient: client,
  );
}

Future<void> settle(HibiraInbox inbox) async {
  for (var i = 0; i < 20 && (inbox.loading || inbox.loadingMore); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('loads the first page with the unread count', () async {
    final api = FakeApi(3);
    final inbox = api.inbox();
    await settle(inbox);
    expect(inbox.items.map((n) => n.title), [
      'Order 3 shipped',
      'Order 2 shipped',
      'Order 1 shipped',
    ]);
    expect(inbox.unread, 3);
    expect(inbox.hasMore, isFalse);
    expect(
      api.requests.single.url.toString(),
      'http://api.test/apps/app1/inbox/me/notifications?limit=20',
    );
    inbox.dispose();
  });

  test('pages with loadMore', () async {
    final api = FakeApi(5);
    final inbox = api.inbox(pageSize: 2);
    await settle(inbox);
    expect(inbox.items.length, 2);
    expect(inbox.hasMore, isTrue);
    await inbox.loadMore();
    await inbox.loadMore();
    expect(inbox.items.map((n) => n.id), [
      'ntf_005',
      'ntf_004',
      'ntf_003',
      'ntf_002',
      'ntf_001',
    ]);
    expect(inbox.hasMore, isFalse);
    inbox.dispose();
  });

  test('marks read and archives, updating the count at once', () async {
    final api = FakeApi(3);
    final inbox = api.inbox();
    await settle(inbox);
    final f = inbox.markRead(['ntf_003']);
    expect(inbox.unread, 2, reason: 'optimistic');
    expect(inbox.items.first.isRead, isTrue);
    await f;
    expect(jsonDecode(api.requests.last.body), {
      'ids': ['ntf_003'],
      'read': true,
    });
    await inbox.archive(['ntf_002']);
    expect(inbox.items.map((n) => n.id), ['ntf_003', 'ntf_001']);
    expect(inbox.unread, 1);
    await inbox.markAllRead();
    expect(jsonDecode(api.requests.last.body), {'all': true, 'read': true});
    expect(inbox.unread, 0);
    inbox.setStatus(InboxStatus.archived);
    await settle(inbox);
    expect(inbox.items.map((n) => n.id), ['ntf_002']);
    inbox.dispose();
  });

  test('rolls back a failed mark', () async {
    final api = FakeApi(2);
    final inbox = api.inbox();
    await settle(inbox);
    api.fail = true;
    await expectLater(
      inbox.archive(['ntf_002']),
      throwsA(isA<InboxException>()),
    );
    expect(inbox.items.length, 2);
    expect(inbox.unread, 2);
    inbox.dispose();
  });

  test('fetches a new token after a 401', () async {
    final api = FakeApi(1);
    final inbox = api.inbox();
    await settle(inbox);
    api.tokens++; // the server now expects the next token
    await inbox.refresh();
    expect(inbox.error, isNull);
    expect(inbox.items.length, 1);
    inbox.dispose();
  });

  test('labels follow the locale', () {
    expect(InboxLabels.forLocale(const Locale('ja')).tabUnread, '未読');
    expect(InboxLabels.forLocale(const Locale('zh', 'TW')).title, '通知');
    expect(
      InboxLabels.forLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      ).tabInbox,
      '收件箱',
    );
    expect(InboxLabels.forLocale(const Locale('de')).title, 'Notifications');
    expect(InboxLabels.en.unread(4), '4 unread');
  });

  testWidgets('bell shows the count and opens the inbox', (tester) async {
    final api = FakeApi(3);
    final inbox = api.inbox();
    InboxNotification? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              NotificationBell(inbox: inbox, onSelect: (n) => selected = n),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byType(NotificationBell));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Order 2 shipped'), findsOneWidget);

    await tester.tap(find.byTooltip('Archive').first);
    await tester.pumpAndSettle();
    expect(find.text('Order 3 shipped'), findsNothing);

    await tester.tap(find.text('Order 2 shipped'));
    await tester.pumpAndSettle();
    expect(selected?.id, 'ntf_002');
    expect(find.text('Order 1 shipped'), findsNothing, reason: 'sheet closed');
    expect(find.text('1'), findsOneWidget);
    inbox.dispose();
  });

  testWidgets('empty and error states', (tester) async {
    final api = FakeApi(0);
    final inbox = api.inbox();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NotificationInbox(inbox: inbox)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You are all caught up.'), findsOneWidget);

    api.fail = true;
    await inbox.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Could not load notifications.'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('You are all caught up.'), findsOneWidget);
    inbox.dispose();
  });
}
