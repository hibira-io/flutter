/// Hibira Push for Flutter: Beams-compatible push notifications on Android
/// (FCM) and iOS (APNs).
///
/// ```dart
/// await HibiraPush.instance.start('YOUR_INSTANCE_ID');
/// await HibiraPush.instance.requestPermission();
/// await HibiraPush.instance.addDeviceInterest('hello');
/// HibiraPush.instance.onMessage.listen((m) => print(m.title));
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// A push notification delivered to the app.
@immutable
class HibiraPushMessage {
  const HibiraPushMessage({this.title, this.body, this.data = const {}});

  factory HibiraPushMessage._fromMap(Map<Object?, Object?> map) {
    final data = map['data'];
    return HibiraPushMessage(
      title: map['title'] as String?,
      body: map['body'] as String?,
      data: data is Map
          ? data.map((k, v) => MapEntry('$k', v))
          : const <String, Object?>{},
    );
  }

  final String? title;
  final String? body;

  /// The `data` you sent with the notification (FCM `data` on Android, the
  /// APNs payload's custom keys on iOS).
  final Map<String, Object?> data;

  @override
  String toString() => 'HibiraPushMessage($title, $body, $data)';
}

/// Gets a Hibira Push user token for [HibiraPush.setUserId].
///
/// The default form GETs your auth URL with `?user_id=<id>` and reads
/// `{"token": "..."}`, like the native SDKs' `PushTokenProvider`. Your backend
/// makes the token with `generateToken` from any Beams-compatible server SDK
/// and your Hibira secret key.
class HibiraPushTokenProvider {
  /// Fetches the token from [authUrl], sending [headers] and [queryParams].
  /// [headers] is called for every request, so it can return a fresh session
  /// token.
  HibiraPushTokenProvider(
    Uri authUrl, {
    FutureOr<Map<String, String>> Function()? headers,
    Map<String, String> queryParams = const {},
    http.Client? httpClient,
  }) : _fetch = ((userId) async {
         final uri = authUrl.replace(
           queryParameters: {
             ...authUrl.queryParameters,
             ...queryParams,
             'user_id': userId,
           },
         );
         final client = httpClient ?? http.Client();
         try {
           final res = await client.get(
             uri,
             headers: {'Accept': 'application/json', ...?await headers?.call()},
           );
           if (res.statusCode != 200) {
             throw HibiraPushException(
               'token endpoint returned ${res.statusCode}',
             );
           }
           final body = jsonDecode(res.body);
           final token = body is Map ? body['token'] : null;
           if (token is! String || token.isEmpty) {
             throw const HibiraPushException(
               'token endpoint response has no "token"',
             );
           }
           return token;
         } finally {
           if (httpClient == null) client.close();
         }
       });

  /// Gets the token any way you like.
  HibiraPushTokenProvider.custom(Future<String> Function(String userId) fetch)
    : _fetch = fetch;

  final Future<String> Function(String userId) _fetch;

  Future<String> fetchToken(String userId) => _fetch(userId);
}

/// A failed Hibira Push call.
class HibiraPushException implements Exception {
  const HibiraPushException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() =>
      'HibiraPushException: $message${code == null ? '' : ' ($code)'}';
}

/// The Hibira Push client. Use [HibiraPush.instance].
class HibiraPush {
  @visibleForTesting
  HibiraPush.withChannel(this._channel) {
    _channel.setMethodCallHandler(_handle);
  }

  static final HibiraPush instance = HibiraPush.withChannel(
    const MethodChannel('io.hibira/push'),
  );

  final MethodChannel _channel;
  final _messages = StreamController<HibiraPushMessage>.broadcast();
  final _opened = StreamController<HibiraPushMessage>.broadcast();
  final _interests = StreamController<Set<String>>.broadcast();
  HibiraPushTokenProvider? _tokenProvider;

  /// Notifications that arrive while the app is in the foreground. They are
  /// not shown by the system; show them in your UI if you want to.
  Stream<HibiraPushMessage> get onMessage => _messages.stream;

  /// Notifications the user tapped while the app was running in the
  /// background. See [getInitialMessage] for the one that launched the app.
  Stream<HibiraPushMessage> get onMessageOpenedApp => _opened.stream;

  /// The device's interests, whenever they change (on this device or after a
  /// sync with the server).
  Stream<Set<String>> get onInterestsChanged => _interests.stream;

  /// Starts the SDK. Call it once at every app start, before the other
  /// methods. [endpoint] overrides the host (default `https://ws.hibira.io`)
  /// for self-hosted servers or another region.
  Future<void> start(String instanceId, {String? endpoint}) =>
      _invoke('start', {'instanceId': instanceId, 'endpoint': ?endpoint});

  /// Asks the user for permission to show notifications (Android 13 and
  /// later, and iOS) and registers with APNs on iOS. Returns whether
  /// notifications are allowed.
  Future<bool> requestPermission() async =>
      await _invoke<bool>('requestPermission') ?? false;

  Future<void> addDeviceInterest(String interest) =>
      _invoke('addDeviceInterest', {'interest': interest});

  Future<void> removeDeviceInterest(String interest) =>
      _invoke('removeDeviceInterest', {'interest': interest});

  Future<void> setDeviceInterests(Iterable<String> interests) =>
      _invoke('setDeviceInterests', {'interests': interests.toList()});

  Future<void> clearDeviceInterests() => _invoke('clearDeviceInterests');

  Future<Set<String>> getDeviceInterests() async {
    final list = await _invoke<List<Object?>>('getDeviceInterests');
    return {...?list?.cast<String>()};
  }

  /// Links this device to [userId] so your server can publish to the user
  /// on all their devices. Call it at every app start while the user is
  /// signed in; the SDK may ask [tokenProvider] for a token again later.
  Future<void> setUserId(String userId, HibiraPushTokenProvider tokenProvider) {
    _tokenProvider = tokenProvider;
    return _invoke('setUserId', {'userId': userId});
  }

  /// Unlinks the user and deletes the device's interests, for sign-out.
  /// The SDK keeps running.
  Future<void> clearAllState() {
    _tokenProvider = null;
    return _invoke('clearAllState');
  }

  /// Stops the SDK and deletes the device from Hibira Push. Call [start]
  /// again to receive notifications.
  Future<void> stop() {
    _tokenProvider = null;
    return _invoke('stop');
  }

  /// The notification the user tapped to launch the app, if any.
  Future<HibiraPushMessage?> getInitialMessage() async {
    final map = await _invoke<Map<Object?, Object?>>('getInitialMessage');
    return map == null ? null : HibiraPushMessage._fromMap(map);
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw HibiraPushException(e.message ?? e.code, code: e.code);
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'onMessage':
        _messages.add(
          HibiraPushMessage._fromMap(args as Map<Object?, Object?>),
        );
      case 'onMessageOpenedApp':
        _opened.add(HibiraPushMessage._fromMap(args as Map<Object?, Object?>));
      case 'onInterestsChanged':
        _interests.add({...(args as List<Object?>).cast<String>()});
      case 'fetchToken':
        final provider = _tokenProvider;
        if (provider == null) {
          throw PlatformException(
            code: 'no-token-provider',
            message: 'call setUserId with a token provider first',
          );
        }
        final userId = (args as Map<Object?, Object?>)['userId'] as String;
        try {
          return await provider.fetchToken(userId);
        } catch (e) {
          throw PlatformException(code: 'token-failed', message: '$e');
        }
    }
    return null;
  }
}
