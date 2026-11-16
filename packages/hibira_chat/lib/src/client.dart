import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hibira/hibira.dart';
import 'package:http/http.dart' as http;

import 'conversation.dart';
import 'conversation_list.dart';
import 'events.dart';
import 'models.dart';

/// Fetches a user token: an HS256 JWT your server signs with the app secret
/// (`{"sub": userId, "exp": ...}`), or one from the Chat API's
/// `POST /chat/tokens`.
typedef ChatTokenProvider = Future<String> Function();

/// An error answered by the Chat API, with its HTTP status (0 when the
/// request did not reach it).
class ChatException implements Exception {
  ChatException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'ChatException($status): $message';
}

/// The Hibira Chat API as the signed-in user (the client routes under
/// `/apps/{appId}/chat/me`).
///
/// Pass a [HibiraClient] that is signed in as the same user
/// (`HibiraOptions(userAuthEndpoint: ...)` and `signIn()`) for live events;
/// without one, call [handleEvent] with events from elsewhere.
class ChatClient {
  ChatClient({
    required this.appId,
    required ChatTokenProvider token,
    this.realtime,
    String host = defaultHost,
    http.Client? httpClient,
  }) : _token = token,
       _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _base = _baseUri(host, appId) {
    final rt = realtime;
    if (rt != null) {
      for (final name in ChatEvent.names) {
        _subs.add(rt.user.on(name).listen((e) => handleEvent(e.name, e.data)));
      }
      _subs.add(
        rt.stateChanges
            .where((s) => s == HibiraConnectionState.connected)
            .listen((_) => notifyLive()),
      );
    }
  }

  static const defaultHost = 'api.hibira.io';
  static const version = '0.1.0';

  /// Your Hibira app ID.
  final String appId;

  /// A [HibiraClient] signed in as the user, for live events.
  final HibiraClient? realtime;

  final ChatTokenProvider _token;
  final http.Client _http;
  final bool _ownsHttp;
  final Uri _base;
  final _subs = <StreamSubscription<Object?>>[];
  final _events = StreamController<ChatEvent>.broadcast(sync: true);
  final _live = StreamController<void>.broadcast(sync: true);
  String? _cachedToken;
  Future<String>? _pendingToken;

  static Uri _baseUri(String host, String appId) {
    var h = host;
    while (h.endsWith('/')) {
      h = h.substring(0, h.length - 1);
    }
    if (!h.startsWith('http://') && !h.startsWith('https://')) h = 'https://$h';
    final u = Uri.parse(h);
    return u.replace(
      pathSegments: [
        ...u.pathSegments.where((s) => s.isNotEmpty),
        'apps',
        appId,
        'chat',
        'me',
      ],
    );
  }

  /// Chat events for this user.
  Stream<ChatEvent> get events => _events.stream;

  /// Fires each time the realtime connection is (re)established, so views
  /// can read what they missed.
  Stream<void> get live => _live.stream;

  /// The token's user (its `sub`), once a token has been fetched; '' before.
  String get userId {
    final t = _cachedToken;
    return t == null ? '' : tokenUser(t);
  }

  /// Fetches the token now (if needed) and returns its user.
  Future<String> currentUser() async => tokenUser(await _getToken());

  /// Feeds an event received on the user's `#server-to-user-<id>` channel.
  /// [data] may be the JSON string or the decoded object. Returns true when
  /// it was a chat event.
  bool handleEvent(String name, Object? data) {
    var d = data;
    if (d is String) {
      try {
        d = jsonDecode(d);
      } on FormatException {
        return false;
      }
    }
    final e = ChatEvent.parse(name, d);
    if (e == null || _events.isClosed) return false;
    _events.add(e);
    return true;
  }

  /// Tell views the realtime connection is (back) up, when you feed events
  /// from your own client.
  void notifyLive() {
    if (!_live.isClosed) _live.add(null);
  }

  Future<String> _getToken({bool force = false}) {
    final t = _cachedToken;
    if (!force && t != null && !_expiresSoon(t)) return Future.value(t);
    return _pendingToken ??= _token()
        .then((t) => _cachedToken = t)
        .whenComplete(() => _pendingToken = null);
  }

  /// The user ID (`sub`) inside a user token, or '' when it cannot be read.
  static String tokenUser(String token) => '${_claims(token)['sub'] ?? ''}';

  static Map<String, Object?> _claims(String token) {
    try {
      final part = base64Url.normalize(token.split('.')[1]);
      return (jsonDecode(utf8.decode(base64Url.decode(part))) as Map)
          .cast<String, Object?>();
    } catch (_) {
      return const {};
    }
  }

  static bool _expiresSoon(String token) {
    final exp = _claims(token)['exp'];
    if (exp is! num) return false;
    return exp - DateTime.now().millisecondsSinceEpoch / 1000 < 30;
  }

  Future<Map<String, Object?>> _call(
    String method,
    List<String> path, {
    Map<String, Object?>? body,
    Map<String, Object?> query = const {},
  }) async {
    final q = <String, String>{
      for (final e in query.entries)
        if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
    };
    final uri = _base.replace(
      pathSegments: [..._base.pathSegments, ...path],
      queryParameters: q.isEmpty ? null : q,
    );
    for (var attempt = 0; ; attempt++) {
      final token = await _getToken(force: attempt > 0);
      final req = http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json';
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      final http.Response res;
      try {
        res = await http.Response.fromStream(await _http.send(req));
      } catch (e) {
        throw ChatException(0, '$e');
      }
      if (res.statusCode == 401 && attempt == 0) continue;
      Map<String, Object?> data = const {};
      try {
        data = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)
            .cast<String, Object?>();
      } catch (_) {}
      if (res.statusCode >= 400) {
        throw ChatException(
          res.statusCode,
          data['error'] as String? ??
              'Chat API request failed (${res.statusCode})',
        );
      }
      return data;
    }
  }

  static Map<String, Object?> _obj(Object? v) =>
      v is Map ? v.cast<String, Object?>() : const {};
  static List<Message> _messages(Object? v) => [
    for (final m in (v is List ? v : const [])) Message.fromJson(_obj(m)),
  ];

  List<String> _conv(String id) => ['conversations', id];

  /// The user's conversations, latest activity first, each with its unread
  /// count.
  Future<ConversationPage> conversations({int? limit, String? before}) async {
    final d = await _call(
      'GET',
      ['conversations'],
      query: {'limit': limit, 'before': before},
    );
    return ConversationPage([
      for (final c in (d['conversations'] as List? ?? const []))
        Conversation.fromJson(_obj(c)),
    ], '${d['next'] ?? ''}');
  }

  Future<Conversation> conversation(String id) async => Conversation.fromJson(
    _obj((await _call('GET', _conv(id)))['conversation']),
  );

  /// Messages oldest first: those after [after] (up to [limit], at most
  /// 200), or the newest [last].
  Future<MessagePage> messages(
    String id, {
    int? after,
    int? last,
    int? limit,
  }) async {
    final d = await _call(
      'GET',
      [..._conv(id), 'messages'],
      query: {'after': after, 'last': last, 'limit': limit},
    );
    return MessagePage(
      _messages(d['messages']),
      (d['last_seq'] as num?)?.toInt() ?? 0,
    );
  }

  /// Messages containing [q] (inside words, ignoring case), newest first.
  Future<SearchPage> search(
    String id,
    String q, {
    String? before,
    int? limit,
  }) async {
    final d = await _call(
      'GET',
      [..._conv(id), 'search'],
      query: {'q': q, 'before': before, 'limit': limit},
    );
    return SearchPage(_messages(d['messages']), '${d['next'] ?? ''}');
  }

  /// Sends a message as the user. [visibleTo] may hold only the user's own
  /// role.
  Future<SendResult> send(
    String id,
    String text, {
    Map<String, Object?>? metadata,
    List<Attachment> attachments = const [],
    String? name,
    List<String>? visibleTo,
  }) async {
    final d = await _call(
      'POST',
      [..._conv(id), 'messages'],
      body: {
        'text': text,
        'metadata': ?metadata,
        if (attachments.isNotEmpty)
          'attachments': [for (final a in attachments) a.toJson()],
        'name': ?name,
        'visible_to': ?visibleTo,
      },
    );
    final push = _obj(d['push']);
    return SendResult(
      Message.fromJson(_obj(d['message'])),
      pushedUsers: (push['users'] as num?)?.toInt(),
      pushError: push['error'] as String?,
    );
  }

  /// Edits the user's own message; [metadata] null keeps it.
  Future<Message> edit(
    String id,
    int seq,
    String text, {
    Map<String, Object?>? metadata,
  }) async => Message.fromJson(
    _obj(
      (await _call(
        'PUT',
        [..._conv(id), 'messages', '$seq'],
        body: {'text': text, 'metadata': ?metadata},
      ))['message'],
    ),
  );

  /// Deletes the user's own message; it keeps its place with `deletedAt`.
  Future<Message> delete(String id, int seq) async => Message.fromJson(
    _obj(
      (await _call('DELETE', [..._conv(id), 'messages', '$seq']))['message'],
    ),
  );

  Future<Message> react(String id, int seq, String emoji) async =>
      Message.fromJson(
        _obj(
          (await _call(
            'POST',
            [..._conv(id), 'messages', '$seq', 'reactions'],
            body: {'emoji': emoji},
          ))['message'],
        ),
      );

  Future<Message> unreact(String id, int seq, String emoji) async =>
      Message.fromJson(
        _obj(
          (await _call(
            'DELETE',
            [..._conv(id), 'messages', '$seq', 'reactions'],
            query: {'emoji': emoji},
          ))['message'],
        ),
      );

  Future<Report> report(String id, int seq, {String reason = ''}) async =>
      Report.fromJson(
        _obj(
          (await _call(
            'POST',
            [..._conv(id), 'messages', '$seq', 'reports'],
            body: {'reason': reason},
          ))['report'],
        ),
      );

  /// Marks the conversation read up to [seq]; returns the user's read_seq
  /// (it never goes back).
  Future<int> read(String id, int seq) async {
    final d = await _call('POST', [..._conv(id), 'read'], body: {'seq': seq});
    return (d['read_seq'] as num?)?.toInt() ?? seq;
  }

  /// Tells the other members the user is typing (or stopped). Nothing is
  /// stored.
  Future<void> typing(String id, {bool typing = true}) async {
    await _call('POST', [..._conv(id), 'typing'], body: {'typing': typing});
  }

  /// Translates message [seq] into [language] (a BCP 47 tag) and keeps it on
  /// the message. Needs a Chat add-on on the hosted service (403 on the free
  /// allowance, 429 past the monthly cap).
  Future<Message> translate(String id, int seq, String language) async =>
      Message.fromJson(
        _obj(
          (await _call(
            'POST',
            [..._conv(id), 'messages', '$seq', 'translations'],
            body: {'language': language},
          ))['message'],
        ),
      );

  /// The user's settings: `{user_id, language}`.
  Future<Map<String, Object?>> me() => _call('GET', const ['']);

  /// Sets the language messages are translated into for this user (a BCP 47
  /// tag such as `ja` or `zh-TW`; null for none).
  Future<String?> setLanguage(String? language) async {
    final d = await _call('PUT', const [''], body: {'language': language});
    final l = d['language'];
    return l is String && l.isNotEmpty ? l : null;
  }

  /// Uploads a file (up to 25 MB) straight to storage; send the returned
  /// [Attachment] in a message's attachments.
  Future<Attachment> upload(
    String id, {
    required String name,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final d = await _call(
      'POST',
      [..._conv(id), 'attachments'],
      body: {'name': name, 'content_type': contentType, 'size': bytes.length},
    );
    final attachment = Attachment.fromJson(_obj(d['attachment']));
    final up = _obj(d['upload']);
    final url = up['url'];
    if (url is! String) throw ChatException(0, 'no upload URL');
    final req = http.Request('${up['method'] ?? 'PUT'}', Uri.parse(url))
      ..bodyBytes = bytes;
    req.headers.clear();
    _obj(up['headers']).forEach((k, v) => req.headers[k] = '$v');
    final res = await _http.send(req);
    await res.stream.drain<void>();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ChatException(res.statusCode, 'upload failed (${res.statusCode})');
    }
    return attachment;
  }

  /// A live view of one conversation. Call [ChatConversation.start], and
  /// [ChatConversation.dispose] when done.
  ChatConversation conversationView(String id, {int pageSize = 50}) =>
      ChatConversation(this, id, pageSize: pageSize);

  /// A live view of the user's conversations with unread counts.
  ChatConversationList conversationList({int pageSize = 30}) =>
      ChatConversationList(this, pageSize: pageSize);

  /// Stops listening to [realtime] and closes the HTTP client it created.
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _events.close();
    _live.close();
    if (_ownsHttp) _http.close();
  }
}
