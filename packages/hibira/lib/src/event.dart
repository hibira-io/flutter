/// An event received on a channel.
class HibiraEvent {
  const HibiraEvent({
    required this.channel,
    required this.name,
    this.data,
    this.userId,
  });

  /// The channel name, or an empty string for connection-level events.
  final String channel;

  /// The event name, such as `my-event`, `client-move` or
  /// `pusher:subscription_succeeded`.
  final String name;

  /// The payload. JSON strings are decoded to maps and lists, as pusher-js
  /// does; other strings are kept as they are.
  final Object? data;

  /// The sender of a client event on a presence channel. The server sets it,
  /// so it cannot be faked by another client.
  final String? userId;

  @override
  String toString() =>
      'HibiraEvent($channel, $name, $data${userId == null ? '' : ', user $userId'})';
}

/// An error from the server (`pusher:error`), the auth endpoint or the
/// connection.
class HibiraException implements Exception {
  const HibiraException(this.message, {this.code, this.status});

  final String message;

  /// The Pusher error or close code (4000-4299), when the server sent one.
  final int? code;

  /// The HTTP status of a failed auth request (403 for a refused
  /// subscription, say).
  final int? status;

  @override
  String toString() {
    final parts = [
      if (code != null) 'code $code',
      if (status != null) 'status $status',
    ];
    return 'HibiraException: $message${parts.isEmpty ? '' : ' (${parts.join(', ')})'}';
  }
}
