# hibira

A [Pusher Channels](https://pusher.com/docs/channels/library_auth_reference/pusher-websockets-protocol/)
protocol (v7) client in pure Dart, for [Hibira](https://hibira.io) and other
Pusher-compatible servers. It runs wherever Dart does: Flutter on Android,
iOS, desktop and the web, and plain Dart on the server.

- Public, private, presence, encrypted (`private-encrypted-`) and cache channels.
- Client events, with the sender's `user_id` on presence channels.
- User sign-in (`pusher:signin`) and events your server sends to a user.
- Reconnects with backoff, resubscribes and signs again by itself.
- Streams for everything, plus `bind` for pusher-js habits.

## Install

```sh
dart pub add hibira
```

## Connect

```dart
import 'package:hibira/hibira.dart';

final hibira = HibiraClient('YOUR_APP_KEY');
await hibira.connect();

final orders = hibira.subscribe('orders');
orders.bind('shipped', (e) => print('order ${e.data} shipped'));
```

The app key is on the app page in the Hibira portal. Never put the app secret
in an app: private and presence channels are signed by your backend.

`HibiraOptions(host: ...)` points the client at another server; the default
is `ws.hibira.io` on port 443 with TLS.

## Private and presence channels

Your backend signs subscriptions with any Pusher server SDK (for Laravel,
[hibira-io/laravel](https://github.com/hibira-io/laravel)). Give the client
the same endpoint pusher-js would use:

```dart
final hibira = HibiraClient(
  'YOUR_APP_KEY',
  options: HibiraOptions(
    authEndpoint: Uri.parse('https://api.example.com/hibira/auth'),
    authHeaders: {'Authorization': 'Bearer $sessionToken'},
  ),
);
```

It gets a form POST with `socket_id` and `channel_name` and returns
`{"auth": "...", "channel_data": "..."}`. To sign some other way, pass
`authorizer: (socketId, channelName) async => HibiraAuth(...)` instead.

```dart
final room = hibira.subscribePresence('presence-room-42');
await room.whenSubscribed;
print('${room.count} here, I am ${room.myId}');

room.memberAdded.listen((m) => print('${m.id} joined: ${m.info}'));
room.memberRemoved.listen((m) => print('${m.id} left'));

room.bind('client-move', (e) => print('${e.userId} moved to ${e.data}'));
room.trigger('client-move', {'x': 3, 'y': 4});
```

Client events need client events turned on for the app in the portal. A
refused subscription (403 from your endpoint for a full room, say) fails
`whenSubscribed` and shows up on `room.errors` with its status.

## Encrypted channels

Subscribe to a `private-encrypted-` channel and return `shared_secret` from
your auth endpoint, as the Pusher server SDKs do when you set an encryption
master key. Events arrive decrypted.

## Users

```dart
final hibira = HibiraClient(
  'YOUR_APP_KEY',
  options: HibiraOptions(
    userAuthEndpoint: Uri.parse('https://api.example.com/hibira/user-auth'),
  ),
);
await hibira.connect();
await hibira.signIn();
hibira.user.bind('notice', (e) => print(e.data));
```

Your server then sends to the user with `sendToUser` (or terminates their
connections). The client signs in again after each reconnect.

## Connection state

```dart
hibira.stateChanges.listen((s) => print(s)); // connecting, connected, reconnecting, disconnected
hibira.errors.listen((e) => print(e));
await hibira.disconnect(); // subscriptions come back on the next connect()
await hibira.dispose();
```

`connect()` fails for good only when the server refuses the connection with
a 4000-4099 close code, such as an unknown app key. Other drops reconnect with
backoff.

## Moving from pusher_channels_flutter

| pusher_channels_flutter | hibira |
|---|---|
| `PusherChannelsFlutter.getInstance().init(apiKey:, cluster:)` | `HibiraClient(key)` |
| `pusher.connect()` | `await hibira.connect()` |
| `pusher.subscribe(channelName:, onEvent:)` | `hibira.subscribe(name).events.listen(...)` |
| `onAuthorizer` | `HibiraOptions(authorizer: ...)` |
| `pusher.trigger(PusherEvent(...))` | `channel.trigger('client-x', data)` |

There is no cluster setting: Hibira uses a host.

## Testing

```sh
dart test                 # unit tests, no network
dart test test/e2e_test.dart  # against a server, see the file header
```

## License

MIT. See [LICENSE](LICENSE).
