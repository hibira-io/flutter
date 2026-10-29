import 'dart:convert';

import 'package:http/http.dart' as http;

import 'event.dart';

/// A signed subscription, as returned by your auth endpoint.
class HibiraAuth {
  const HibiraAuth({required this.auth, this.channelData, this.sharedSecret});

  /// Reads the endpoint's JSON: `{"auth": ..., "channel_data": ...,
  /// "shared_secret": ...}`.
  factory HibiraAuth.fromJson(Map<String, Object?> json) {
    final auth = json['auth'];
    if (auth is! String || auth.isEmpty) {
      throw const HibiraException('auth response has no "auth" field');
    }
    final channelData = json['channel_data'];
    return HibiraAuth(
      auth: auth,
      channelData: channelData == null
          ? null
          : channelData is String
          ? channelData
          : jsonEncode(channelData),
      sharedSecret: json['shared_secret'] as String?,
    );
  }

  /// `<app key>:<signature>`.
  final String auth;

  /// Presence channels: the JSON string with `user_id` and `user_info`.
  final String? channelData;

  /// Encrypted channels: the base64 channel key.
  final String? sharedSecret;
}

/// A signed user, as returned by your user authentication endpoint.
class HibiraUserAuth {
  const HibiraUserAuth({required this.auth, required this.userData});

  /// Reads the endpoint's JSON: `{"auth": ..., "user_data": ...}`.
  factory HibiraUserAuth.fromJson(Map<String, Object?> json) {
    final auth = json['auth'];
    final userData = json['user_data'];
    if (auth is! String || userData == null) {
      throw const HibiraException(
        'user auth response needs "auth" and "user_data"',
      );
    }
    return HibiraUserAuth(
      auth: auth,
      userData: userData is String ? userData : jsonEncode(userData),
    );
  }

  final String auth;

  /// The JSON string with the user's `id` (and anything else you put in).
  final String userData;
}

/// Signs a private, presence or encrypted subscription yourself instead of
/// [HibiraOptions.authEndpoint]. Throw a [HibiraException] to refuse.
typedef HibiraAuthorizer =
    Future<HibiraAuth> Function(String socketId, String channelName);

/// Signs the user in yourself instead of [HibiraOptions.userAuthEndpoint].
typedef HibiraUserAuthenticator =
    Future<HibiraUserAuth> Function(String socketId);

/// POSTs a form to [endpoint] the way pusher-js does and returns the JSON
/// object it answers with.
Future<Map<String, Object?>> postAuth(
  http.Client client,
  Uri endpoint,
  Map<String, String> fields,
  Map<String, String> headers,
) async {
  final http.Response res;
  try {
    res = await client.post(
      endpoint,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
        ...headers,
      },
      body: fields,
    );
  } catch (e) {
    throw HibiraException('auth request to $endpoint failed: $e');
  }
  Object? body;
  try {
    body = jsonDecode(res.body);
  } catch (_) {
    body = null;
  }
  if (res.statusCode != 200 || body is! Map<String, Object?>) {
    var message = 'auth endpoint returned ${res.statusCode}';
    if (body is Map && body['error'] != null) message = '${body['error']}';
    throw HibiraException(message, status: res.statusCode);
  }
  return body;
}
