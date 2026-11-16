# hibira_chat

Client for the [Hibira Chat API](https://hibira.io/chat-api) in pure Dart:
conversations, message history with paging, live messages, edits,
reactions, typing, read receipts and translations. It runs wherever Dart
does: Flutter on Android, iOS, desktop and the web, and plain Dart.

- `ChatClient` calls the Chat API's user routes with a user token.
- Live `chat.*` events come from a [`hibira`](https://pub.dev/packages/hibira)
  `HibiraClient` signed in as the same user.
- `ChatConversation` keeps one conversation up to date; `ChatConversationList`
  keeps the user's conversations, with unread counts.

## Install

```sh
dart pub add hibira hibira_chat
```

## Your server

The app needs two things from your backend, both signed with the app
secret, so the secret never ships in the app:

1. A **user token** for the HTTP calls: an HS256 JWT `{"sub": userId, "exp": ...}`
   (or one from the Chat API's `POST /apps/{app_id}/chat/tokens`).
2. A **user authentication endpoint** for the realtime connection, the same
   one `pusher.signin()` uses. With the Node `pusher` library:

```js
app.post('/chat/token', requireLogin, (req, res) => {
  const token = jwt.sign({ sub: req.user.id }, process.env.HIBIRA_SECRET,
    { algorithm: 'HS256', expiresIn: '1h' });
  res.json({ token });
});

app.post('/pusher/user-auth', requireLogin, (req, res) => {
  res.json(pusher.authenticateUser(req.body.socket_id, { id: req.user.id }));
});
```

Your server also creates conversations and adds members (`PUT
/apps/{app_id}/chat/conversations/{id}`); apps cannot.

## Use

```dart
import 'package:hibira/hibira.dart';
import 'package:hibira_chat/hibira_chat.dart';

final hibira = HibiraClient(
  'YOUR_APP_KEY',
  options: HibiraOptions(
    userAuthEndpoint: Uri.parse('https://api.example.com/pusher/user-auth'),
    authHeaders: {'Authorization': 'Bearer $sessionToken'},
  ),
);
await hibira.connect();
hibira.signIn();

final chat = ChatClient(
  appId: 'YOUR_APP_ID',
  token: () => api.fetchChatToken(),
  realtime: hibira,
);

// The user's conversations with unread counts.
final inbox = chat.conversationList()..start();

// One conversation.
final room = chat.conversationView('trip-1')..start();
```

Both views have a `state` and a `changes` stream, so a widget rebuilds with
a `StreamBuilder`:

```dart
StreamBuilder<ChatConversationState>(
  stream: room.changes,
  initialData: room.state,
  builder: (context, snap) {
    final s = snap.data!;
    return ListView(
      children: [
        if (s.hasOlder)
          TextButton(onPressed: room.loadOlder, child: const Text('Earlier')),
        for (final m in s.messages)
          ListTile(
            title: Text(m.isDeleted ? 'Message deleted' : m.textFor(myLanguage)),
            subtitle: Text(m.name ?? m.sender ?? ''),
          ),
        if (s.typing.isNotEmpty) Text('${s.typing.join(', ')} typing…'),
      ],
    );
  },
);

// In the composer
onChanged: (_) => room.typing(),
onSubmitted: (text) => room.send(text),
// When the newest message is on screen
room.markRead();
// When the screen closes
room.dispose();
```

`ChatConversation` re-reads the newest messages each time the connection
comes back, so edits, deletes and reactions made while the app was offline
show up. `ChatClient` has every user route: `conversations`,
`conversation`, `messages` (`after`, `last`, `limit`), `search`, `send`,
`edit`, `delete`, `react`, `unreact`, `report`, `read`, `typing`,
`translate`, `setLanguage`, `me` and `upload` (straight to storage, up to
25 MB; send the returned `Attachment` in a message). Errors are
`ChatException` with the HTTP status.

## Translations

Set the user's language once (`chat.setLanguage('ja')`) and messages
from others arrive translated a moment later (`chat.message_updated`).
`message.textFor('ja')` gives the translation when there is one, else the
original `text`; `room.translate(seq, 'ja')` translates one message on
request. Translation needs a Chat add-on on the hosted service.

## 中文摘要

`hibira_chat` 是 Hibira Chat API 的純 Dart 用戶端（Flutter 各平台與 Dart VM 都能用）：`ChatClient` 呼叫使用者路由（對話、訊息紀錄、傳送、編輯、刪除、表情回應、檢舉、已讀、輸入中、翻譯、使用者語言、附件上傳），並從已登入的 `HibiraClient` 收 `chat.*` 即時事件。`conversationView(id)` 提供單一對話的訊息、往前翻頁、輸入中與已讀狀態，重連後自動補齊；`conversationList()` 提供含未讀數的對話列表，兩者都有 `state` 和 `changes` 串流，可直接接 `StreamBuilder`。App 需要你的後端提供使用者 token（用 app secret 簽的 JWT）和使用者認證端點（`pusher.authenticateUser`）；建立對話、加成員仍由你的後端呼叫。

## License

MIT. See [LICENSE](LICENSE).
