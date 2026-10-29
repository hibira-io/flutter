import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pinenacl/x25519.dart' show ByteList, SecretBox;

import 'auth.dart';
import 'event.dart';
import 'options.dart';
import 'socket.dart';

part 'channel.dart';

/// The state of a [HibiraClient]'s connection.
enum HibiraConnectionState { disconnected, connecting, connected, reconnecting }

/// A Pusher Channels protocol (v7) client for Hibira and other
/// Pusher-compatible servers.
///
/// Public channels need only the app key. Private, presence and encrypted
/// channels are signed by your own backend: set
/// [HibiraOptions.authEndpoint] (the same endpoint pusher-js would use) or
/// [HibiraOptions.authorizer]. Never put the app secret in an app.
class HibiraClient {
  HibiraClient(this.key, {this.options = const HibiraOptions()})
    : _http = options.httpClient ?? http.Client(),
      _ownsHttp = options.httpClient == null {
    user = HibiraUser._(this);
  }

  static const version = '0.1.0';
  static const protocol = 7;

  /// The app key from the Hibira portal.
  final String key;

  final HibiraOptions options;

  /// The signed-in user, after [signIn].
  late final HibiraUser user;

  final http.Client _http;
  final bool _ownsHttp;
  final _random = Random();

  HibiraConnectionState _state = HibiraConnectionState.disconnected;
  String? _socketId;
  HibiraSocket? _socket;
  StreamSubscription<String>? _socketSub;
  final Map<String, HibiraChannel> _channels = {};
  bool _wantConnection = false;
  bool _disposed = false;
  int _attempt = 0;
  Timer? _retryTimer;
  Timer? _activityTimer;
  Timer? _pongTimer;
  Duration? _serverTimeout;
  Completer<void>? _connecting;
  int? _lastErrorCode; // of the last pusher:error on this connection

  final _stateChanges = StreamController<HibiraConnectionState>.broadcast();
  final _events = StreamController<HibiraEvent>.broadcast();
  final _errors = StreamController<HibiraException>.broadcast();

  HibiraConnectionState get state => _state;

  /// Every change of [state].
  Stream<HibiraConnectionState> get stateChanges => _stateChanges.stream;

  /// This connection's socket id, null until connected.
  String? get socketId => _socketId;

  /// Every event on every channel (pusher_internal events excluded).
  Stream<HibiraEvent> get events => _events.stream;

  /// Errors the server sent (`pusher:error`), failed connections and
  /// refused sign-ins. Subscription errors go to [HibiraChannel.errors].
  Stream<HibiraException> get errors => _errors.stream;

  /// Calls [callback] for [event] on any channel.
  StreamSubscription<HibiraEvent> bind(
    String event,
    void Function(HibiraEvent event) callback,
  ) => _events.stream.where((e) => e.name == event).listen(callback);

  /// Opens the connection. Completes once connected; fails when the server
  /// refuses the connection for good (close codes 4000-4099, such as an
  /// unknown app key). Channels you subscribed to are (re)subscribed once the
  /// connection is up.
  Future<void> connect() {
    _checkNotDisposed();
    if (_state == HibiraConnectionState.connected) return Future.value();
    _wantConnection = true;
    final connecting = _connecting ??= Completer<void>();
    if (_socket == null && _retryTimer == null) _open();
    return connecting.future;
  }

  /// Closes the connection and stops reconnecting. Subscriptions are kept and
  /// come back on the next [connect].
  Future<void> disconnect() async {
    _wantConnection = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _failConnecting(const HibiraException('disconnected'));
    final socket = _socket;
    if (socket != null) {
      await socket.close(1000, 'client disconnect');
    } else {
      _setState(HibiraConnectionState.disconnected);
    }
  }

  /// Disconnects and releases everything. The client cannot be used again.
  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    _socketSub?.cancel();
    _stopTimers();
    for (final ch in _channels.values) {
      ch._remove();
    }
    _channels.clear();
    user._dispose();
    if (_ownsHttp) _http.close();
    await _stateChanges.close();
    await _events.close();
    await _errors.close();
  }

  /// Subscribes to a channel, or returns the existing subscription. A
  /// `presence-` channel comes back as a [HibiraPresenceChannel].
  HibiraChannel subscribe(String channelName) {
    _checkNotDisposed();
    final existing = _channels[channelName];
    if (existing != null) return existing;
    final HibiraChannel ch;
    if (channelName.startsWith('presence-')) {
      ch = HibiraPresenceChannel._(this, channelName);
    } else if (channelName.startsWith('private-encrypted-')) {
      ch = _EncryptedChannel._(this, channelName);
    } else {
      ch = HibiraChannel._(this, channelName);
    }
    _channels[channelName] = ch;
    if (_state == HibiraConnectionState.connected) _subscribe(ch);
    return ch;
  }

  /// [subscribe] for a `presence-` channel.
  HibiraPresenceChannel subscribePresence(String channelName) {
    if (!channelName.startsWith('presence-')) {
      throw ArgumentError.value(
        channelName,
        'channelName',
        'presence channel names start with "presence-"',
      );
    }
    return subscribe(channelName) as HibiraPresenceChannel;
  }

  void unsubscribe(String channelName) {
    final ch = _channels.remove(channelName);
    if (ch == null) return;
    if (ch.isSubscribed && _state == HibiraConnectionState.connected) {
      _send({
        'event': 'pusher:unsubscribe',
        'data': {'channel': channelName},
      });
    }
    ch._remove();
  }

  /// The subscription to [channelName], or null.
  HibiraChannel? channel(String channelName) => _channels[channelName];

  Iterable<HibiraChannel> get channels => _channels.values;

  /// Sends a client event (its name must start with `client-`) on a private
  /// or presence channel you are subscribed to. The app needs client events
  /// turned on. Returns false when not connected.
  bool trigger(String channelName, String event, Object? data) {
    if (!event.startsWith('client-')) {
      throw ArgumentError.value(
        event,
        'event',
        'client event names start with "client-"',
      );
    }
    if (channelName.startsWith('private-encrypted-')) {
      throw ArgumentError.value(
        channelName,
        'channelName',
        'client events are not supported on encrypted channels',
      );
    }
    if (!channelName.startsWith('private-') &&
        !channelName.startsWith('presence-')) {
      throw ArgumentError.value(
        channelName,
        'channelName',
        'client events need a private or presence channel',
      );
    }
    if (_state != HibiraConnectionState.connected) return false;
    return _send({'event': event, 'channel': channelName, 'data': data});
  }

  /// Signs this connection in as a user (`pusher:signin`), so your server can
  /// send to the user with `sendToUser` and terminate their connections.
  /// Needs [HibiraOptions.userAuthEndpoint] or
  /// [HibiraOptions.userAuthenticator]. The client signs in again after every
  /// reconnect. Completes once the server accepts.
  Future<void> signIn() {
    _checkNotDisposed();
    if (options.userAuthEndpoint == null && options.userAuthenticator == null) {
      throw StateError('set userAuthEndpoint or userAuthenticator to sign in');
    }
    user._wanted = true;
    if (user.isSignedIn) return Future.value();
    final waiting = user._waiting ??= Completer<void>();
    if (_state == HibiraConnectionState.connected) _signIn();
    return waiting.future;
  }

  // ---- connection ----------------------------------------------------------

  Uri get _uri {
    final port = options.port ?? (options.useTLS ? 443 : 80);
    return Uri(
      scheme: options.useTLS ? 'wss' : 'ws',
      host: options.host,
      port: port,
      path: '/app/${Uri.encodeComponent(key)}',
      queryParameters: {
        'protocol': '$protocol',
        'client': 'dart',
        'version': version,
        'flash': 'false',
      },
    );
  }

  void _open() {
    _retryTimer = null;
    _setState(
      _attempt == 0
          ? HibiraConnectionState.connecting
          : HibiraConnectionState.reconnecting,
    );
    final HibiraSocket socket;
    try {
      socket = (options.connector ?? connectWebSocket)(_uri);
    } catch (e) {
      _errors.add(HibiraException('could not open $_uri: $e'));
      _scheduleReconnect(1006);
      return;
    }
    _socket = socket;
    _lastErrorCode = null;
    socket.ready.then(
      (_) {},
      onError: (Object e) {
        if (_socket == socket && !_disposed) {
          _errors.add(HibiraException('could not connect to $_uri: $e'));
        }
      },
    );
    _socketSub = socket.messages.listen(
      (text) {
        if (_socket != socket) return;
        _touch();
        _handleMessage(text);
      },
      onError: (Object _) {},
      onDone: () {
        if (_socket != socket) return;
        _closed(socket.closeCode ?? 1006, socket.closeReason ?? '');
      },
      cancelOnError: false,
    );
  }

  void _touch() {
    _pongTimer?.cancel();
    _pongTimer = null;
    _activityTimer?.cancel();
    if (_state != HibiraConnectionState.connected) return;
    var limit = options.activityTimeout;
    final server = _serverTimeout;
    if (server != null && server < limit) limit = server;
    _activityTimer = Timer(limit, () {
      _send({'event': 'pusher:ping', 'data': {}});
      _pongTimer = Timer(options.pongTimeout, () {
        _pongTimer = null;
        _socket?.close(4201, 'pong timeout');
        // Some transports never report the close of a dead socket.
        final socket = _socket;
        Timer(const Duration(seconds: 2), () {
          if (_socket == socket && socket != null) {
            _closed(4201, 'pong timeout');
          }
        });
      });
    });
  }

  void _stopTimers() {
    _activityTimer?.cancel();
    _activityTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
  }

  void _closed(int code, String reason) {
    _socketSub?.cancel();
    _socketSub = null;
    _socket = null;
    _socketId = null;
    _stopTimers();
    for (final ch in _channels.values) {
      ch._reset();
    }
    user._reset();
    if (_disposed) return;
    final fatal = code >= 4000 && code <= 4099;
    if (fatal) {
      _wantConnection = false;
      final error = HibiraException(
        reason.isEmpty ? 'connection refused' : reason,
        code: code,
      );
      // The server usually sends the same error as pusher:error first.
      if (_lastErrorCode != code) _errors.add(error);
      _failConnecting(error);
    }
    if (_wantConnection && options.autoReconnect) {
      _scheduleReconnect(code);
    } else {
      if (!fatal && _wantConnection) {
        _failConnecting(HibiraException('connection closed', code: code));
      }
      _wantConnection = false;
      _setState(HibiraConnectionState.disconnected);
    }
  }

  void _scheduleReconnect(int code) {
    if (!_wantConnection || !options.autoReconnect) {
      _setState(HibiraConnectionState.disconnected);
      return;
    }
    _setState(HibiraConnectionState.reconnecting);
    Duration delay;
    if (code >= 4200 && code <= 4299 && _attempt == 0) {
      delay = Duration.zero; // the server asks for an immediate reconnect
    } else if (code >= 4100 && code <= 4199) {
      delay = Duration(seconds: 1 + _attempt); // over capacity: back off
    } else {
      final seconds = min(30, pow(2, _attempt).toDouble());
      delay = Duration(
        milliseconds: (seconds * 1000 * (0.5 + _random.nextDouble() / 2))
            .round(),
      );
    }
    _attempt++;
    _retryTimer = Timer(delay, () {
      if (_wantConnection && !_disposed) _open();
    });
  }

  void _failConnecting(HibiraException error) {
    final connecting = _connecting;
    _connecting = null;
    if (connecting != null && !connecting.isCompleted) {
      connecting.completeError(error);
      connecting.future.ignore();
    }
  }

  void _setState(HibiraConnectionState s) {
    if (s == _state || _disposed) return;
    _state = s;
    _stateChanges.add(s);
  }

  bool _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null) return false;
    try {
      socket.send(jsonEncode(message));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _emitGlobal(HibiraEvent e) {
    if (!_disposed) _events.add(e);
  }

  // ---- protocol ------------------------------------------------------------

  void _handleMessage(String text) {
    final msg = _decode(text);
    if (msg is! Map || msg['event'] is! String) return;
    final event = msg['event'] as String;
    final data = _decode(msg['data']);
    final channelName = msg['channel'] is String
        ? msg['channel'] as String
        : '';
    final userId = msg['user_id']?.toString();
    switch (event) {
      case 'pusher:connection_established':
        final d = data is Map ? data : const {};
        _socketId = d['socket_id']?.toString();
        final timeout = d['activity_timeout'];
        _serverTimeout = timeout is num
            ? Duration(milliseconds: (timeout * 1000).round())
            : null;
        _attempt = 0;
        _setState(HibiraConnectionState.connected);
        _touch();
        final connecting = _connecting;
        _connecting = null;
        if (connecting != null && !connecting.isCompleted) {
          connecting.complete();
        }
        for (final ch in _channels.values.toList()) {
          _subscribe(ch);
        }
        if (user._wanted) _signIn();
        return;
      case 'pusher:error':
        final d = data is Map ? data : const {};
        final code = d['code'] is num ? (d['code'] as num).toInt() : null;
        final error = HibiraException('${d['message'] ?? 'error'}', code: code);
        _lastErrorCode = code;
        _errors.add(error);
        if (code == 4009) user._failed(error);
        return;
      case 'pusher:ping':
        _send({'event': 'pusher:pong', 'data': {}});
        return;
      case 'pusher:pong':
        return;
      case 'pusher:signin_success':
        final d = data is Map ? data : const {};
        user._signedIn(_decode(d['user_data']));
        return;
      case 'pusher:subscription_error':
        final ch = _channels[channelName];
        final d = data is Map ? data : const {};
        ch?._failed(
          HibiraException(
            '${d['error'] ?? d['type'] ?? 'subscription refused'}',
            status: d['status'] is num ? (d['status'] as num).toInt() : null,
          ),
        );
        return;
    }
    if (channelName.startsWith('#server-to-user-')) {
      user._handle(event, data);
      if (!event.startsWith('pusher_internal:')) {
        _emitGlobal(HibiraEvent(channel: channelName, name: event, data: data));
      }
      return;
    }
    final ch = _channels[channelName];
    if (ch != null) {
      final e = ch._handle(event, data, userId);
      if (e != null) _emitGlobal(e);
    } else if (!event.startsWith('pusher_internal:')) {
      _emitGlobal(
        HibiraEvent(
          channel: channelName,
          name: event,
          data: data,
          userId: userId,
        ),
      );
    }
  }

  Future<void> _subscribe(HibiraChannel ch) async {
    final channelName = ch.name;
    if (!ch.isPrivate && !ch.isPresence) {
      _send({
        'event': 'pusher:subscribe',
        'data': {'channel': channelName},
      });
      return;
    }
    final sid = _socketId;
    HibiraAuth auth;
    try {
      auth = await _authorize(channelName);
    } on HibiraException catch (e) {
      if (sid == _socketId && _channels[channelName] == ch) ch._failed(e);
      return;
    }
    // The connection may have dropped, or the channel been unsubscribed,
    // while the auth request was in flight.
    if (sid != _socketId || _channels[channelName] != ch) return;
    if (ch is _EncryptedChannel) {
      if (auth.sharedSecret == null) {
        ch._failed(
          HibiraException(
            'no shared_secret for encrypted channel $channelName',
          ),
        );
        return;
      }
      try {
        ch._setKey(auth.sharedSecret);
      } catch (_) {
        ch._failed(HibiraException('bad shared_secret for $channelName'));
        return;
      }
    }
    ch._setChannelData(auth.channelData);
    _send({
      'event': 'pusher:subscribe',
      'data': {
        'channel': channelName,
        'auth': auth.auth,
        'channel_data': ?auth.channelData,
      },
    });
  }

  Future<HibiraAuth> _authorize(String channelName) async {
    final socketId = _socketId;
    if (socketId == null) throw const HibiraException('not connected');
    final authorizer = options.authorizer;
    if (authorizer != null) return authorizer(socketId, channelName);
    final endpoint = options.authEndpoint;
    if (endpoint == null) {
      throw HibiraException(
        'set authEndpoint or authorizer to subscribe to $channelName',
      );
    }
    final json = await postAuth(_http, endpoint, {
      ...options.authParams,
      'socket_id': socketId,
      'channel_name': channelName,
    }, options.authHeaders);
    return HibiraAuth.fromJson(json);
  }

  Future<void> _signIn() async {
    final sid = _socketId;
    if (sid == null) return;
    HibiraUserAuth auth;
    try {
      final authenticator = options.userAuthenticator;
      if (authenticator != null) {
        auth = await authenticator(sid);
      } else {
        auth = HibiraUserAuth.fromJson(
          await postAuth(_http, options.userAuthEndpoint!, {
            ...options.authParams,
            'socket_id': sid,
          }, options.authHeaders),
        );
      }
    } on HibiraException catch (e) {
      if (sid == _socketId) {
        _errors.add(e);
        user._failed(e);
      }
      return;
    }
    if (sid != _socketId) return;
    _send({
      'event': 'pusher:signin',
      'data': {'auth': auth.auth, 'user_data': auth.userData},
    });
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('HibiraClient was disposed');
  }
}

/// The user this connection is signed in as, after [HibiraClient.signIn].
/// Events your server sends with `sendToUser` arrive here.
class HibiraUser {
  HibiraUser._(this._client);

  final HibiraClient _client;
  bool _wanted = false;
  String? _id;
  Object? _data;
  Completer<void>? _waiting;
  final _events = StreamController<HibiraEvent>.broadcast();

  /// The user's id, from the `user_data` your endpoint signed.
  String? get id => _id;

  /// The whole `user_data` your endpoint signed.
  Object? get data => _data;

  bool get isSignedIn => _id != null;

  /// Events sent to this user.
  Stream<HibiraEvent> get events => _events.stream;

  /// Events named [event] sent to this user.
  Stream<HibiraEvent> on(String event) =>
      _events.stream.where((e) => e.name == event);

  StreamSubscription<HibiraEvent> bind(
    String event,
    void Function(HibiraEvent event) callback,
  ) => on(event).listen(callback);

  void _signedIn(Object? userData) {
    _data = userData;
    _id = userData is Map ? userData['id']?.toString() : null;
    if (_id != null) {
      // Server-to-user channels need no auth: the server checks that this
      // socket is signed in as the user.
      _client._send({
        'event': 'pusher:subscribe',
        'data': {'channel': '#server-to-user-$_id'},
      });
    }
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  void _failed(HibiraException error) {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.completeError(error);
  }

  void _handle(String event, Object? data) {
    if (event.startsWith('pusher_internal:')) return;
    _events.add(
      HibiraEvent(channel: '#server-to-user-$_id', name: event, data: data),
    );
  }

  void _reset() {
    _id = null;
  }

  void _dispose() {
    _events.close();
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) {
      waiting.completeError(const HibiraException('client disposed'));
      waiting.future.ignore();
    }
  }
}

/// Pusher sends most payloads as JSON inside a string; decode it when it is
/// JSON, as pusher-js does, and keep plain strings as they are.
Object? _decode(Object? value) {
  if (value is! String) return value;
  try {
    return jsonDecode(value);
  } on FormatException {
    return value;
  }
}
