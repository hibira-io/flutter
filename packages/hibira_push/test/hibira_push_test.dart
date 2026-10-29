import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hibira_push/hibira_push.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.hibira/push.test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late HibiraPush push;

  setUp(() {
    calls = [];
    push = HibiraPush.withChannel(channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getDeviceInterests':
          return ['a', 'b'];
        case 'requestPermission':
          return true;
        case 'addDeviceInterest':
          if (call.arguments['interest'] == 'bad name!') {
            throw PlatformException(code: 'Invalid', message: 'bad interest');
          }
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Sends a call from the native side to Dart and returns Dart's answer.
  Future<Object?> fromNative(String method, Object? args) async {
    final codec = const StandardMethodCodec();
    final reply = await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
    return reply == null ? null : codec.decodeEnvelope(reply);
  }

  test('forwards calls to the native SDK', () async {
    await push.start('instance-1', endpoint: 'https://push.example.com');
    await push.addDeviceInterest('hello');
    await push.setDeviceInterests({'x', 'y'});
    expect(await push.getDeviceInterests(), {'a', 'b'});
    expect(await push.requestPermission(), isTrue);
    expect(calls.map((c) => c.method), [
      'start',
      'addDeviceInterest',
      'setDeviceInterests',
      'getDeviceInterests',
      'requestPermission',
    ]);
    expect(calls.first.arguments, {
      'instanceId': 'instance-1',
      'endpoint': 'https://push.example.com',
    });
    expect(calls[2].arguments, {
      'interests': ['x', 'y'],
    });
  });

  test('native errors become HibiraPushException', () async {
    expect(
      () => push.addDeviceInterest('bad name!'),
      throwsA(
        isA<HibiraPushException>()
            .having((e) => e.code, 'code', 'Invalid')
            .having((e) => e.message, 'message', 'bad interest'),
      ),
    );
  });

  test('delivers messages from native', () async {
    final message = push.onMessage.first;
    final opened = push.onMessageOpenedApp.first;
    final interests = push.onInterestsChanged.first;
    await fromNative('onMessage', {
      'title': 'Hi',
      'body': 'There',
      'data': {'order': '7'},
    });
    await fromNative('onMessageOpenedApp', {
      'data': {'screen': 'orders'},
    });
    await fromNative('onInterestsChanged', ['a']);
    final m = await message;
    expect(m.title, 'Hi');
    expect(m.body, 'There');
    expect(m.data, {'order': '7'});
    expect((await opened).data, {'screen': 'orders'});
    expect(await interests, {'a'});
  });

  test('answers native token requests with the token provider', () async {
    late Uri requested;
    final mock = MockClient((req) async {
      requested = req.url;
      expect(req.headers['Authorization'], 'Bearer s1');
      return http.Response('{"token":"jwt-1"}', 200);
    });
    await push.setUserId(
      'user-1',
      HibiraPushTokenProvider(
        Uri.parse('https://api.example.com/push-auth?app=1'),
        headers: () async => {'Authorization': 'Bearer s1'},
        httpClient: mock,
      ),
    );
    expect(calls.last.arguments, {'userId': 'user-1'});
    expect(await fromNative('fetchToken', {'userId': 'user-1'}), 'jwt-1');
    expect(requested.queryParameters, {'app': '1', 'user_id': 'user-1'});
  });

  test('token provider failures reach native as errors', () async {
    await push.setUserId(
      'user-1',
      HibiraPushTokenProvider.custom((_) async => throw Exception('offline')),
    );
    expect(
      () => fromNative('fetchToken', {'userId': 'user-1'}),
      throwsA(isA<PlatformException>()),
    );
    await push.clearAllState();
    expect(
      () => fromNative('fetchToken', {'userId': 'user-1'}),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'no-token-provider',
        ),
      ),
    );
  });
}
