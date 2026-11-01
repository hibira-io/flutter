# hibira_inbox

A notification inbox for Flutter apps on [Hibira](https://hibira.io): a bell
with an unread badge and a feed with read/unread and archive, updated live in
every open app and tab. Your server sends one request; Hibira stores the
notifications, delivers them in real time and pushes them through Hibira Push
to users who are offline.

It is the Flutter side of [`@hibira-io/inbox`](https://github.com/hibira-io/inbox)
(React, Vue and React Native components and the server SDK), and works with
the same API.

```sh
flutter pub add hibira_inbox
```

## 1. Send from your server

Use `inbox.send()` from [`@hibira-io/inbox`](https://github.com/hibira-io/inbox#1-send-from-your-server),
or a signed `POST /apps/{app_id}/inbox/notifications` from any language (see
the [API reference](https://github.com/hibira-io/pusher-server/blob/master/docs/inbox.md)):

```json
{ "users": ["ann"], "title": "Order #1042 shipped", "url": "/orders/1042", "data": { "orderId": 1042 } }
```

## 2. Give the signed-in user a token

Your server signs a short-lived user token: an HS256 JWT with the app secret,
`{"sub": userId, "exp": ...}`, at most 30 days ahead (`inbox.userToken(id)`
in the Node SDK). Never put the app secret in the app.

## 3. Show the bell

```dart
import 'package:hibira/hibira.dart';
import 'package:hibira_inbox/hibira_inbox.dart';

final client = HibiraClient(
  'YOUR_APP_KEY',
  options: HibiraOptions(userAuthEndpoint: Uri.parse('https://api.example.com/hibira/user-auth')),
);
await client.connect();
await client.signIn();

final inbox = HibiraInbox(
  appId: hibiraAppId,
  token: () async => (await api.get('/inbox-token'))['token'] as String,
  client: client, // live updates; without it the inbox refreshes every minute
);

AppBar(
  actions: [
    NotificationBell(
      inbox: inbox,
      onSelect: (n) => Navigator.pushNamed(context, n.url ?? '/'),
    ),
  ],
);
```

The bell opens the inbox in a bottom sheet. Put `NotificationInbox(inbox: inbox)`
on a page of its own instead, or build your own list from `inbox.items`,
`inbox.unread` and `NotificationTile`. `HibiraInbox` is a `ChangeNotifier`;
`inbox.arrivals` streams each notification that arrives live (for a snack
bar). Call `inbox.dispose()` when the user signs out.

| `HibiraInbox` | |
|---|---|
| `markRead` / `markUnread` / `archive` / `unarchive` | update the server and the list at once; rolled back on error |
| `markAllRead` / `archiveAll` | |
| `setStatus(InboxStatus.unread)` | `inbox`, `unread`, `read`, `archived`, `all` |
| `refresh` / `loadMore` | |

Labels follow the app's locale (en, zh-TW, zh-CN, ja, ko, th, vi). Override
any string with `labels: InboxLabels.of(context).copyWith(tabArchived: 'Done')`.
Colors come from your `Theme`.

## Limits

Notifications are kept 7 days on Free, 30 days on Hobby and Starter, 90 days
on Pro and up; each user keeps the newest 1,000.

## 中文摘要

`hibira_inbox` 是 Hibira 通知中心的 Flutter 版：鈴鐺與未讀數、已讀／未讀、封存，透過使用者的 server-to-user 頻道即時同步，離線使用者由 Hibira Push 推播。伺服器送出通知，App 以伺服器簽發的使用者 token 直接讀取自己的通知。內建繁中、簡中、日、韓、泰、越與英文介面，顏色跟隨 App 的 Theme。

## License

MIT
