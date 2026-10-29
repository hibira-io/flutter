import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// The WebSocket under a [HibiraClient]. The default uses
/// `package:web_socket_channel`, which works on the Dart VM, Flutter and the
/// web; tests and custom transports can supply their own.
abstract class HibiraSocket {
  /// Text frames from the server. The stream closes when the socket does.
  Stream<String> get messages;

  /// Completes when the socket is open, or fails when it cannot be opened.
  Future<void> get ready;

  /// The close code, once [messages] is done.
  int? get closeCode;

  /// The close reason, once [messages] is done.
  String? get closeReason;

  void send(String text);

  Future<void> close([int? code, String? reason]);
}

/// Opens a [HibiraSocket] to [uri].
typedef HibiraSocketConnector = HibiraSocket Function(Uri uri);

/// The default [HibiraSocketConnector].
HibiraSocket connectWebSocket(Uri uri) =>
    _ChannelSocket(WebSocketChannel.connect(uri));

class _ChannelSocket implements HibiraSocket {
  _ChannelSocket(this._channel);

  final WebSocketChannel _channel;

  @override
  late final Stream<String> messages = _channel.stream.map(
    (m) => m is String ? m : utf8.decode(m as List<int>),
  );

  @override
  Future<void> get ready => _channel.ready;

  @override
  int? get closeCode => _channel.closeCode;

  @override
  String? get closeReason => _channel.closeReason;

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close([int? code, String? reason]) =>
      _channel.sink.close(code, reason);
}
