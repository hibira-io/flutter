import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hibira/hibira.dart';
import 'package:http/http.dart' as http;

import 'notification.dart';

/// Fetches a user token: a JWT your server signs with the app secret
/// (`{"sub": userId, "exp": ...}`), for example from an endpoint behind
/// your login.
typedef InboxTokenProvider = Future<String> Function();

/// An error answer of the inbox API.
class InboxException implements Exception {
  InboxException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'InboxException($status): $message';
}

/// The signed-in user's notification inbox: pages of notifications, the
/// unread count, and read/unread and archive, kept live through the user's
/// server-to-user channel when [client] is signed in. Listen to it (it is a
/// [ChangeNotifier]) or use [NotificationBell] and [NotificationInbox].
class HibiraInbox extends ChangeNotifier {
  HibiraInbox({
    required this.appId,
    required InboxTokenProvider token,
    this.client,
    String host = 'api.hibira.io',
    this.pageSize = 20,
    Duration pollInterval = const Duration(minutes: 1),
    http.Client? httpClient,
  }) : _token = token,
       _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _base = Uri.parse(
         '${host.startsWith('http') ? host : 'https://$host'}/apps/${Uri.encodeComponent(appId)}/inbox/me',
       ) {
    final c = client;
    if (c != null) {
      _subs.add(
        c.user.on('inbox.notification').listen((e) => _onNotification(e.data)),
      );
      _subs.add(c.user.on('inbox.updated').listen((e) => _onUpdated(e.data)));
      _subs.add(c.user.on('inbox.deleted').listen((e) => _onDeleted(e.data)));
      _subs.add(
        c.stateChanges
            .where((s) => s == HibiraConnectionState.connected)
            .listen((_) => refresh()),
      );
    } else if (pollInterval > Duration.zero) {
      _poll = Timer.periodic(pollInterval, (_) => refresh());
    }
    refresh();
  }

  /// Your Hibira app ID.
  final String appId;

  /// A [HibiraClient] signed in as the user, for live updates.
  final HibiraClient? client;
  final int pageSize;

  final InboxTokenProvider _token;
  final http.Client _http;
  final bool _ownsHttp;
  final Uri _base;
  final _subs = <StreamSubscription<Object?>>[];
  final _arrivals = StreamController<InboxNotification>.broadcast();
  Timer? _poll;
  String? _cachedToken;
  Future<String>? _pendingToken;
  int _generation = 0;
  bool _disposed = false;

  InboxStatus _status = InboxStatus.inbox;
  List<InboxNotification> _items = const [];
  int _unread = 0;
  String _next = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _ready = false;
  Object? _error;

  InboxStatus get status => _status;

  /// The current tab's notifications, newest first.
  List<InboxNotification> get items => _items;

  /// Unread, not archived: the number on the bell.
  int get unread => _unread;
  bool get hasMore => _next.isNotEmpty;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;

  /// The first page has loaded.
  bool get ready => _ready;
  Object? get error => _error;

  /// Each notification that arrives live.
  Stream<InboxNotification> get arrivals => _arrivals.stream;

  void _set(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  Future<String> _getToken({bool force = false}) {
    final t = _cachedToken;
    if (!force && t != null && !_expiresSoon(t)) return Future.value(t);
    return _pendingToken ??= _token()
        .then((t) => _cachedToken = t)
        .whenComplete(() => _pendingToken = null);
  }

  static bool _expiresSoon(String token) {
    try {
      final part = base64Url.normalize(token.split('.')[1]);
      final exp =
          (jsonDecode(utf8.decode(base64Url.decode(part))) as Map)['exp'];
      if (exp is! int) return false;
      return exp - DateTime.now().millisecondsSinceEpoch ~/ 1000 < 30;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, Object?>> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    bool retried = false,
  }) async {
    final token = await _getToken(force: retried);
    final uri = _base.replace(
      path: '${_base.path}$path',
      queryParameters: query,
    );
    final req = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(req));
    if (res.statusCode == 401 && !retried) {
      return _call(method, path, body: body, query: query, retried: true);
    }
    Map<String, Object?> data = const {};
    try {
      data = (jsonDecode(res.body) as Map).cast<String, Object?>();
    } catch (_) {}
    if (res.statusCode >= 400) {
      throw InboxException(
        res.statusCode,
        data['error'] as String? ?? 'inbox request failed (${res.statusCode})',
      );
    }
    return data;
  }

  List<InboxNotification> _parse(Object? list) => [
    for (final n in (list as List? ?? const []))
      InboxNotification.fromJson((n as Map).cast<String, Object?>()),
  ];

  /// Loads the first page of the current tab again.
  Future<void> refresh() async {
    final gen = ++_generation;
    _set(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _call(
        'GET',
        '/notifications',
        query: {
          'limit': '$pageSize',
          if (_status.query.isNotEmpty) 'status': _status.query,
        },
      );
      if (gen != _generation) return;
      _set(() {
        _items = _parse(page['notifications']);
        _next = page['next'] as String? ?? '';
        _unread = (page['unread'] as num?)?.toInt() ?? 0;
        _loading = false;
        _ready = true;
      });
    } catch (e) {
      if (gen == _generation) {
        _set(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  /// Loads the next page, if there is one.
  Future<void> loadMore() async {
    if (_next.isEmpty || _loadingMore) return;
    final gen = _generation;
    _set(() => _loadingMore = true);
    try {
      final page = await _call(
        'GET',
        '/notifications',
        query: {
          'limit': '$pageSize',
          'before': _next,
          if (_status.query.isNotEmpty) 'status': _status.query,
        },
      );
      if (gen != _generation) return;
      final have = {for (final n in _items) n.id};
      _set(() {
        _items = [
          ..._items,
          ..._parse(page['notifications']).where((n) => !have.contains(n.id)),
        ];
        _next = page['next'] as String? ?? '';
        _unread = (page['unread'] as num?)?.toInt() ?? _unread;
        _loadingMore = false;
      });
    } catch (e) {
      if (gen == _generation) {
        _set(() {
          _loadingMore = false;
          _error = e;
        });
      }
    }
  }

  /// Shows another tab.
  void setStatus(InboxStatus status) {
    if (status == _status) return;
    _set(() {
      _status = status;
      _items = const [];
      _next = '';
    });
    refresh();
  }

  void _apply(
    Iterable<String>? ids, {
    bool? read,
    bool? archived,
    int? unread,
  }) {
    final want = ids?.toSet();
    final now = DateTime.now();
    var count = _unread;
    final items = <InboxNotification>[];
    for (final n in _items) {
      if (want != null && !want.contains(n.id)) {
        items.add(n);
        continue;
      }
      final m = n.copyWith(
        readAt: read == null ? null : () => read ? (n.readAt ?? now) : null,
        archivedAt: archived == null
            ? null
            : () => archived ? (n.archivedAt ?? now) : null,
      );
      count += (m.isUnread ? 1 : 0) - (n.isUnread ? 1 : 0);
      if (_status.matches(m)) items.add(m);
    }
    if (want == null && read == true) count = 0;
    _set(() {
      _items = items;
      _unread = unread ?? (count < 0 ? 0 : count);
    });
  }

  Future<void> _mark(List<String>? ids, {bool? read, bool? archived}) async {
    if (ids != null && ids.isEmpty) return;
    final items = _items, unread = _unread;
    _apply(ids, read: read, archived: archived);
    try {
      final res = await _call(
        'POST',
        '/notifications/mark',
        body: {
          if (ids == null) 'all': true else 'ids': ids,
          'read': ?read,
          'archived': ?archived,
        },
      );
      _set(() => _unread = (res['unread'] as num?)?.toInt() ?? _unread);
    } catch (e) {
      _set(() {
        _items = items;
        _unread = unread;
        _error = e;
      });
      rethrow;
    }
  }

  Future<void> markRead(List<String> ids) => _mark(ids, read: true);
  Future<void> markUnread(List<String> ids) => _mark(ids, read: false);
  Future<void> archive(List<String> ids) => _mark(ids, archived: true);
  Future<void> unarchive(List<String> ids) => _mark(ids, archived: false);
  Future<void> markAllRead() => _mark(null, read: true);
  Future<void> archiveAll() => _mark(null, archived: true);

  void _onNotification(Object? data) {
    if (data is! Map || data['notification'] is! Map) return;
    final n = InboxNotification.fromJson(
      (data['notification'] as Map).cast<String, Object?>(),
    );
    if (_items.any((o) => o.id == n.id)) return;
    _set(() {
      if (_status.matches(n)) _items = [n, ..._items];
      if (n.isUnread) _unread++;
    });
    _arrivals.add(n);
  }

  void _onUpdated(Object? data) {
    if (data is! Map || data['ids'] is! List) return;
    _apply(
      (data['ids'] as List).cast<String>(),
      read: data['read'] as bool?,
      archived: data['archived'] as bool?,
      unread: (data['unread'] as num?)?.toInt(),
    );
  }

  void _onDeleted(Object? data) {
    if (data is! Map || data['ids'] is! List) return;
    final gone = (data['ids'] as List).toSet();
    _set(() {
      _items = _items.where((n) => !gone.contains(n.id)).toList();
      _unread = (data['unread'] as num?)?.toInt() ?? _unread;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _poll?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _arrivals.close();
    if (_ownsHttp) _http.close();
    super.dispose();
  }
}
