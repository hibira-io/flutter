import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hibira/hibira.dart';
import 'package:hibira_flutterflow/custom_code/actions/hibira_connect.dart';
import 'package:hibira_flutterflow/custom_code/actions/index.dart';
import 'package:hibira_flutterflow/custom_code/widgets/index.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('connection status follows the shared state', (tester) async {
    await tester.pumpWidget(_app(const HibiraConnectionStatus()));
    expect(find.text('Offline'), findsOneWidget);

    HibiraFF.state.value = HibiraConnectionState.connecting;
    await tester.pump();
    expect(find.text('Connecting'), findsOneWidget);

    HibiraFF.state.value = HibiraConnectionState.connected;
    await tester.pump();
    expect(find.text('Live'), findsOneWidget);
    HibiraFF.state.value = HibiraConnectionState.disconnected;
  });

  testWidgets('presence count and listener render before connecting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            const HibiraPresenceCount(channelName: 'presence-room'),
            HibiraEventListener(
              channelName: 'orders',
              eventName: 'shipped',
              onEvent: (data) async {},
            ),
          ],
        ),
      ),
    );
    expect(find.text('0 online'), findsOneWidget);

    await tester.pumpWidget(_app(const SizedBox()));
    expect(await hibiraPresenceMembers('presence-room'), isEmpty);
  });

  test('actions are safe before hibiraConnect', () async {
    expect(await hibiraTrigger('private-x', 'client-y', {'a': 1}), isFalse);
    await hibiraSubscribe('orders', 'shipped', (data) async {});
    await hibiraUnsubscribe('orders');
    await hibiraDisconnect();
  });
}
