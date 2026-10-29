part of 'client.dart';

/// A channel subscription made by [HibiraClient.subscribe].
///
/// Listen with [bind], [on] or [events]. Subscriptions survive reconnects:
/// the client subscribes again (and signs again) whenever the connection
/// comes back.
class HibiraChannel {
  HibiraChannel._(this._client, this.name);

  final HibiraClient _client;

  /// The channel name, such as `orders`, `private-user-1` or
  /// `presence-room-42`.
  final String name;

  bool _subscribed = false;
  bool _removed = false;
  Completer<void>? _waiting;
  final _events = StreamController<HibiraEvent>.broadcast();
  final _errors = StreamController<HibiraException>.broadcast();
  final _count = StreamController<int>.broadcast();

  /// True once the server has accepted the subscription (until a disconnect).
  bool get isSubscribed => _subscribed;

  bool get isPrivate => name.startsWith('private-');

  bool get isEncrypted => name.startsWith('private-encrypted-');

  bool get isPresence => name.startsWith('presence-');

  /// Every event on this channel, including `pusher:subscription_succeeded`
  /// and, on presence channels, `pusher:member_added` and
  /// `pusher:member_removed`.
  Stream<HibiraEvent> get events => _events.stream;

  /// Events named [event].
  Stream<HibiraEvent> on(String event) =>
      _events.stream.where((e) => e.name == event);

  /// Calls [callback] for every [event] on this channel. Cancel the returned
  /// subscription to unbind.
  StreamSubscription<HibiraEvent> bind(
    String event,
    void Function(HibiraEvent event) callback,
  ) => on(event).listen(callback);

  /// The auth endpoint refused the subscription (403 for a full room, say),
  /// the server rejected it, or an encrypted event could not be decrypted.
  Stream<HibiraException> get errors => _errors.stream;

  /// Subscriber counts, when subscription count events are on for the app.
  Stream<int> get subscriptionCount => _count.stream;

  /// Completes once the server has accepted the subscription, right away if
  /// it already has. Fails with a [HibiraException] when the subscription is
  /// refused.
  Future<void> get whenSubscribed {
    if (_subscribed) return Future.value();
    return (_waiting ??= Completer<void>()).future;
  }

  /// Sends a client event (its name must start with `client-`) to the other
  /// subscribers, not back to you. Only on private and presence channels, and
  /// the app needs client events turned on. Returns false when the channel is
  /// not subscribed yet.
  bool trigger(String event, Object? data) {
    if (!_subscribed) return false;
    return _client.trigger(name, event, data);
  }

  void unsubscribe() => _client.unsubscribe(name);

  // ---- called by HibiraClient ----------------------------------------------

  void _setChannelData(String? channelData) {}

  void _reset() {
    _subscribed = false;
  }

  void _remove() {
    _reset();
    _removed = true;
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) {
      waiting.completeError(
        const HibiraException('unsubscribed before the subscription succeeded'),
      );
      // Nobody may be listening any more; don't report it as unhandled.
      waiting.future.ignore();
    }
    _events.close();
    _errors.close();
    _count.close();
  }

  void _failed(HibiraException error) {
    if (_removed) return;
    _errors.add(error);
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.completeError(error);
  }

  HibiraEvent? _succeeded(Object? data) {
    _subscribed = true;
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
    return _emit('pusher:subscription_succeeded', data, null);
  }

  HibiraEvent? _emit(String event, Object? data, String? userId) {
    if (_removed) return null;
    final e = HibiraEvent(
      channel: name,
      name: event,
      data: data,
      userId: userId,
    );
    _events.add(e);
    return e;
  }

  /// Handles a message from the server. Returns the event as it should be
  /// reported to [HibiraClient.events], or null for internal events.
  HibiraEvent? _handle(String event, Object? data, String? userId) {
    switch (event) {
      case 'pusher_internal:subscription_succeeded':
        return _succeeded(data);
      case 'pusher_internal:subscription_count':
        if (data is Map && data['subscription_count'] is num) {
          final count = (data['subscription_count'] as num).toInt();
          if (!_removed) _count.add(count);
          return _emit('pusher:subscription_count', data, null);
        }
        return null;
    }
    if (event.startsWith('pusher_internal:')) return null;
    return _emit(event, data, userId);
  }
}

/// A member of a presence channel.
class HibiraMember {
  const HibiraMember(this.id, this.info);

  /// The `user_id` your auth endpoint put in the channel data.
  final String id;

  /// The `user_info` your auth endpoint put in the channel data.
  final Object? info;

  @override
  bool operator ==(Object other) => other is HibiraMember && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'HibiraMember($id, $info)';
}

/// A presence channel: a [HibiraChannel] that also knows who is subscribed.
class HibiraPresenceChannel extends HibiraChannel {
  HibiraPresenceChannel._(super.client, super.name) : super._();

  final Map<String, HibiraMember> _members = {};
  String? _myId;
  final _added = StreamController<HibiraMember>.broadcast();
  final _removedMembers = StreamController<HibiraMember>.broadcast();

  /// Members by id, you included. Empty until subscribed.
  Map<String, HibiraMember> get members => Map.unmodifiable(_members);

  /// The number of members, you included.
  int get count => _members.length;

  /// Your member id, from the auth endpoint's channel data.
  String? get myId => _myId;

  /// You, once subscribed.
  HibiraMember? get me => _myId == null ? null : _members[_myId];

  HibiraMember? member(String id) => _members[id];

  Stream<HibiraMember> get memberAdded => _added.stream;

  Stream<HibiraMember> get memberRemoved => _removedMembers.stream;

  @override
  void _setChannelData(String? channelData) {
    if (channelData == null) return;
    final data = _decode(channelData);
    if (data is Map && data['user_id'] != null) {
      _myId = '${data['user_id']}';
    }
  }

  @override
  void _reset() {
    super._reset();
    _members.clear();
  }

  @override
  void _remove() {
    super._remove();
    _added.close();
    _removedMembers.close();
  }

  @override
  HibiraEvent? _handle(String event, Object? data, String? userId) {
    switch (event) {
      case 'pusher_internal:subscription_succeeded':
        _members.clear();
        final presence = data is Map ? data['presence'] : null;
        final hash = presence is Map ? presence['hash'] : null;
        if (hash is Map) {
          hash.forEach(
            (id, info) => _members['$id'] = HibiraMember('$id', info),
          );
        }
        return _succeeded(presence ?? data);
      case 'pusher_internal:member_added':
        if (data is Map && data['user_id'] != null) {
          final m = HibiraMember('${data['user_id']}', data['user_info']);
          final known = _members.containsKey(m.id);
          _members[m.id] = m;
          if (!known && !_removed) {
            _added.add(m);
            return _emit('pusher:member_added', {
              'id': m.id,
              'info': m.info,
            }, null);
          }
        }
        return null;
      case 'pusher_internal:member_removed':
        if (data is Map && data['user_id'] != null) {
          final m = _members.remove('${data['user_id']}');
          if (m != null && !_removed) {
            _removedMembers.add(m);
            return _emit('pusher:member_removed', {
              'id': m.id,
              'info': m.info,
            }, null);
          }
        }
        return null;
    }
    return super._handle(event, data, userId);
  }
}

/// An encrypted channel (`private-encrypted-`): events are decrypted with the
/// key your auth endpoint returns as `shared_secret`.
class _EncryptedChannel extends HibiraChannel {
  _EncryptedChannel._(super.client, super.name) : super._();

  SecretBox? _box;

  void _setKey(String? sharedSecret) {
    if (sharedSecret == null) {
      _box = null;
      return;
    }
    _box = SecretBox(Uint8List.fromList(base64Decode(sharedSecret)));
  }

  String? _decrypt(Object? data) {
    final box = _box;
    if (box == null || data is! Map) return null;
    final nonce = data['nonce'], ciphertext = data['ciphertext'];
    if (nonce is! String || ciphertext is! String) return null;
    try {
      final plain = box.decrypt(
        ByteList(base64Decode(ciphertext)),
        nonce: base64Decode(nonce),
      );
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  @override
  HibiraEvent? _handle(String event, Object? data, String? userId) {
    if (event.startsWith('pusher_internal:') || event.startsWith('pusher:')) {
      return super._handle(event, data, userId);
    }
    final plain = _decrypt(data);
    if (plain != null) return super._handle(event, _decode(plain), userId);
    _retry(event, data, userId);
    return null;
  }

  /// The key may have been rotated: sign again for a fresh one and retry
  /// once, as pusher-js does.
  Future<void> _retry(String event, Object? data, String? userId) async {
    String? plain;
    try {
      final auth = await _client._authorize(name);
      _setKey(auth.sharedSecret);
      plain = _decrypt(data);
    } on HibiraException {
      plain = null;
    }
    if (plain == null) {
      _failed(HibiraException('could not decrypt $event on $name'));
      return;
    }
    final e = super._handle(event, _decode(plain), userId);
    if (e != null) _client._emitGlobal(e);
  }
}
