# hibira_push example

The example app is in the repository root, together with the Channels client:
[hibira-io/flutter/example](https://github.com/hibira-io/flutter/tree/main/example).

```dart
import 'package:hibira_push/hibira_push.dart';

Future<void> setUpPush() async {
  final push = HibiraPush.instance;
  await push.start('YOUR_INSTANCE_ID');
  await push.requestPermission();
  await push.addDeviceInterest('hello');
  push.onMessage.listen((m) => print('${m.title}: ${m.body}'));
}
```
