# hibira_push

Push notifications for Flutter apps with [Hibira Push](https://hibira.io), the
Beams-compatible push service of Hibira. This plugin wraps the native
[hibira-push-android](https://github.com/hibira-io/hibira-push-android) (FCM)
and [hibira-push-ios](https://github.com/hibira-io/hibira-push-ios) (APNs)
SDKs.

- Android 7 (API 24) and later, iOS 15 and later.
- Device interests, authenticated users, foreground messages and taps.
- Works next to other Firebase plugins.

For realtime channels, see [`hibira`](https://pub.dev/packages/hibira).

## Install

```sh
flutter pub add hibira_push
```

### Android

Delivery uses Firebase Cloud Messaging, so the app needs a Firebase project.

1. Add the app in the Firebase console and put `google-services.json` in
   `android/app`.
2. Apply the Google services plugin. In `android/settings.gradle.kts`:

   ```kotlin
   plugins {
       // ...
       id("com.google.gms.google-services") version "4.4.2" apply false
   }
   ```

   and in `android/app/build.gradle.kts`:

   ```kotlin
   plugins {
       // ...
       id("com.google.gms.google-services")
   }
   ```

3. Upload the FCM service account JSON in the Hibira portal (app page, Push
   notifications).

The plugin pulls `hibira-push-android` from JitPack by itself.

### iOS

The iOS SDK is a Swift package, so the app needs Flutter's Swift Package
Manager support (on by default in recent Flutter; otherwise run
`flutter config --enable-swift-package-manager`).

1. In Xcode, add the **Push Notifications** capability to the Runner target,
   and **Background Modes > Remote notifications** if you send silent pushes.
2. Upload your APNs `.p8` key in the Hibira portal (app page, Push
   notifications).
3. In `ios/Runner/AppDelegate.swift`, let the plugin see notifications while
   the app is open and when the user taps one:

   ```swift
   import UserNotifications

   // in application(_:didFinishLaunchingWithOptions:), before super:
   UNUserNotificationCenter.current().delegate = self
   ```

## Use

```dart
import 'package:hibira_push/hibira_push.dart';

final push = HibiraPush.instance;

await push.start('YOUR_INSTANCE_ID');
await push.requestPermission();
await push.addDeviceInterest('hello');
```

Call `start` at every app start. The instance ID is on the app's Push
notifications card in the portal. `requestPermission` shows the system prompt
(Android 13 and later, and iOS) and registers with APNs on iOS.

```dart
push.onMessage.listen((m) {
  // Arrived while the app is open. The system shows nothing; you decide.
  print('${m.title}: ${m.body} ${m.data}');
});

push.onMessageOpenedApp.listen((m) => openScreen(m.data));
final launchedBy = await push.getInitialMessage();
```

### Interests

```dart
await push.setDeviceInterests({'news', 'team-7'});
await push.removeDeviceInterest('news');
final interests = await push.getDeviceInterests();
push.onInterestsChanged.listen(print);
```

### Authenticated users

Link the device to a user so your server can publish to the user on all their
devices:

```dart
await push.setUserId(
  'user-1',
  HibiraPushTokenProvider(
    Uri.parse('https://api.example.com/push-auth'),
    headers: () async => {'Authorization': 'Bearer ${await session.token()}'},
  ),
);
```

The provider GETs `https://api.example.com/push-auth?user_id=user-1`, and
your backend returns `{"token": "..."}` made with `generateToken` from any
Beams-compatible server SDK and your Hibira secret key. Use
`HibiraPushTokenProvider.custom((userId) async => ...)` to fetch the token
some other way. Call `setUserId` at every start while the user is signed in,
and `clearAllState()` on sign-out.

### Host

The SDKs use `https://ws.hibira.io`. For a self-hosted server or another
region, pass `start('...', endpoint: 'https://push.example.com')`.

## Moving from pusher_beams

| pusher_beams | hibira_push |
|---|---|
| `PusherBeams.instance.start(id)` | `HibiraPush.instance.start(id)` |
| `addDeviceInterest` / `setDeviceInterests` / `getDeviceInterests` | same names |
| `setUserId(id, BeamsAuthProvider()..authUrl = ..., onSuccess, onError)` | `await setUserId(id, HibiraPushTokenProvider(Uri.parse(...)))` |
| `onMessageReceivedInTheForeground(cb)` | `onMessage.listen(cb)` |
| `onInterestChanges(cb)` | `onInterestsChanged.listen(cb)` |

Devices register again on first start with the new SDK.

## License

MIT. See [LICENSE](LICENSE).
