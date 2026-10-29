import 'dart:async';
import 'dart:convert';

import 'package:hibira/hibira.dart';

/// An in-memory [HibiraSocket]: tests play the server.
class FakeSocket implements HibiraSocket {
  FakeSocket(this.uri);

  final Uri uri;
  final _incoming = StreamController<String>();
  final sent = <Map<String, Object?>>[];
  int? _code;
  String? _reason;
  bool get isClosed => _incoming.isClosed;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  int? get closeCode => _code;

  @override
  String? get closeReason => _reason;

  @override
  void send(String text) => sent.add(jsonDecode(text) as Map<String, Object?>);

  @override
  Future<void> close([int? code, String? reason]) async {
    serverClose(code ?? 1005, reason ?? '');
  }

  /// Sends a server message. [data] is JSON-encoded into a string, as the
  /// Pusher protocol does.
  void push(String event, {Object? data, String? channel, String? userId}) {
    _incoming.add(
      jsonEncode({
        'event': event,
        'data': data is String ? data : jsonEncode(data ?? {}),
        'channel': ?channel,
        'user_id': ?userId,
      }),
    );
  }

  void establish([String socketId = '123.456', int activityTimeout = 120]) =>
      push(
        'pusher:connection_established',
        data: {'socket_id': socketId, 'activity_timeout': activityTimeout},
      );

  void serverClose(int code, [String reason = '']) {
    if (_incoming.isClosed) return;
    _code = code;
    _reason = reason;
    _incoming.close();
  }

  Iterable<Map<String, Object?>> sentEvents(String event) =>
      sent.where((m) => m['event'] == event);
}

/// Hands out [FakeSocket]s and remembers them.
class FakeServer {
  final sockets = <FakeSocket>[];

  FakeSocket get last => sockets.last;

  HibiraSocket connect(Uri uri) {
    final s = FakeSocket(uri);
    sockets.add(s);
    return s;
  }
}

Future<void> pump() => Future<void>.delayed(Duration.zero);
