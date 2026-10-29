import 'package:http/http.dart' as http;

import 'auth.dart';
import 'socket.dart';

/// Connection settings for a [HibiraClient].
class HibiraOptions {
  const HibiraOptions({
    this.host = 'ws.hibira.io',
    this.port,
    this.useTLS = true,
    this.authEndpoint,
    this.authHeaders = const {},
    this.authParams = const {},
    this.authorizer,
    this.userAuthEndpoint,
    this.userAuthenticator,
    this.autoReconnect = true,
    this.activityTimeout = const Duration(seconds: 120),
    this.pongTimeout = const Duration(seconds: 30),
    this.httpClient,
    this.connector,
  });

  /// WebSocket host. Hibira: `ws.hibira.io`.
  final String host;

  /// Defaults to 443 with TLS and 80 without.
  final int? port;

  final bool useTLS;

  /// URL that signs private, presence and encrypted subscriptions: it gets a
  /// form POST with `socket_id` and `channel_name` (plus [authParams]) and
  /// returns `{"auth": ..., "channel_data": ...}`, the same endpoint pusher-js
  /// would use.
  final Uri? authEndpoint;

  /// Extra headers for both auth endpoints, such as
  /// `{'Authorization': 'Bearer <token>'}`.
  final Map<String, String> authHeaders;

  /// Extra form fields for both auth endpoints.
  final Map<String, String> authParams;

  /// Signs subscriptions yourself instead of [authEndpoint].
  final HibiraAuthorizer? authorizer;

  /// URL for [HibiraClient.signIn]: it gets a form POST with `socket_id` and
  /// returns `{"auth": ..., "user_data": ...}`.
  final Uri? userAuthEndpoint;

  /// Signs the user in yourself instead of [userAuthEndpoint].
  final HibiraUserAuthenticator? userAuthenticator;

  /// Reconnect after a dropped connection, with backoff.
  final bool autoReconnect;

  /// Idle time before the client pings the server. The server's own
  /// activity timeout wins when it is shorter.
  final Duration activityTimeout;

  /// How long to wait for any reply to a ping before reconnecting.
  final Duration pongTimeout;

  /// HTTP client for the auth requests. One is created (and closed by
  /// [HibiraClient.dispose]) when this is null.
  final http.Client? httpClient;

  /// Opens the WebSocket. Defaults to `package:web_socket_channel`.
  final HibiraSocketConnector? connector;
}
