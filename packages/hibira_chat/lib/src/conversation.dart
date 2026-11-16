import 'dart:async';

import 'client.dart';
import 'events.dart';
import 'models.dart';

/// What a [ChatConversation] shows.
class ChatConversationState {
  const ChatConversationState({
    this.conversation,
    this.messages = const [],
    this.loading = true,
    this.loadingOlder = false,
    this.hasOlder = false,
    this.typing = const {},
    this.reads = const {},
    this.closed = false,
    this.error,
  });

  final Conversation? conversation;

  /// Loaded messages ordered by seq, without repeats.
  final List<Message> messages;
  final bool loading;
  final bool loadingOlder;

  /// Older messages can be loaded with [ChatConversation.loadOlder].
  final bool hasOlder;

  /// Members typing right now (not the user).
  final Set<String> typing;

  /// Each member's read_seq, kept live from `chat.read`.
  final Map<String, int> reads;

  /// The conversation was deleted or the user removed from it.
  final bool closed;
  final Object? error;

  int get lastSeq => messages.isEmpty ? 0 : messages.last.seq;

  /// Members other than [userId] who have read message [seq].
  List<String> readBy(int seq, String userId) => [
    for (final e in reads.entries)
      if (e.key != userId && e.value >= seq) e.key,
  ];

  ChatConversationState copyWith({
    Conversation? conversation,
    List<Message>? messages,
    bool? loading,
    bool? loadingOlder,
    bool? hasOlder,
    Set<String>? typing,
    Map<String, int>? reads,
    bool? closed,
    Object? Function()? error,
  }) => ChatConversationState(
    conversation: conversation ?? this.conversation,
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    hasOlder: hasOlder ?? this.hasOlder,
    typing: typing ?? this.typing,
    reads: reads ?? this.reads,
    closed: closed ?? this.closed,
    error: error == null ? this.error : error(),
  );
}

/// One conversation kept up to date: the newest page of messages, older
/// pages on demand, live messages, edits, reactions, typing and read
/// receipts, and a catch-up read each time the realtime connection comes
/// back. Read [state] and listen to [changes] (for example with a
/// `StreamBuilder`).
class ChatConversation {
  ChatConversation(this.client, this.conversationId, {this.pageSize = 50});

  /// How long a typing indicator shows without another `chat.typing`.
  static const typingShow = Duration(seconds: 8);

  final ChatClient client;
  final String conversationId;
  final int pageSize;

  ChatConversationState _state = const ChatConversationState();
  final _changes = StreamController<ChatConversationState>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  final _typingTimers = <String, Timer>{};
  int _floor = -1;
  Future<void>? _refreshing;
  bool _again = false;
  DateTime? _typingSent;
  Timer? _typingOff;
  bool _disposed = false;

  ChatConversationState get state => _state;

  /// Each new [state].
  Stream<ChatConversationState> get changes => _changes.stream;

  void _set(ChatConversationState s) {
    if (_disposed) return;
    _state = s;
    _changes.add(s);
  }

  /// Starts loading and listening; safe to call again.
  void start() {
    if (_subs.isNotEmpty || _disposed) return;
    _subs.add(
      client.events
          .where((e) => e.conversationId == conversationId)
          .listen(apply),
    );
    _subs.add(client.live.listen((_) => refresh()));
    refresh();
  }

  static List<Message> _merge(List<Message> list, List<Message> page) {
    if (page.isEmpty) return list;
    final bySeq = {for (final m in list) m.seq: m};
    for (final m in page) {
      bySeq[m.seq] = m;
    }
    return bySeq.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
  }

  void _add(List<Message> page) =>
      _set(_state.copyWith(messages: _merge(_state.messages, page)));

  /// Reads what is new, and re-reads the newest messages for edits, deletes
  /// and reactions made while the connection was down. Calls made while one
  /// runs fold into one more.
  Future<void> refresh() {
    final running = _refreshing;
    if (running != null) {
      _again = true;
      return running;
    }
    Future<void> run() async {
      do {
        _again = false;
        await _load();
      } while (_again && !_disposed);
    }

    return _refreshing = run().whenComplete(() => _refreshing = null);
  }

  Future<void> _load() async {
    try {
      if (_state.conversation == null || _state.messages.isEmpty) {
        final c = await client.conversation(conversationId);
        _set(
          _state.copyWith(
            conversation: c,
            reads: {
              ..._state.reads,
              for (final m in c.members)
                m.userId: _max(m.readSeq, _state.reads[m.userId]),
            },
          ),
        );
      }
      var after = _state.lastSeq;
      if (after > 0) {
        while (true) {
          final page = await client.messages(
            conversationId,
            after: after,
            limit: 200,
          );
          _add(page.messages);
          if (page.messages.length < 200) break;
          after = page.messages.last.seq;
        }
      }
      final count = _state.messages.length.clamp(pageSize, 200);
      final page = await client.messages(conversationId, last: count);
      if (_floor < 0) {
        _floor = page.messages.isEmpty
            ? page.lastSeq + 1
            : page.messages.first.seq;
      }
      _set(
        _state.copyWith(
          messages: _merge(_state.messages, page.messages),
          loading: false,
          hasOlder: _floor > 1,
          error: () => null,
        ),
      );
    } on ChatException catch (e) {
      _set(
        _state.copyWith(
          loading: false,
          closed: e.status == 404 ? true : null,
          error: () => e,
        ),
      );
    } catch (e) {
      _set(_state.copyWith(loading: false, error: () => e));
    }
  }

  static int _max(int a, int? b) => b == null || a > b ? a : b;

  /// Loads the page of messages before the oldest one loaded.
  Future<void> loadOlder() async {
    if (_floor <= 1 || _state.loadingOlder) return;
    _set(_state.copyWith(loadingOlder: true));
    try {
      var after = _floor - 1 - pageSize;
      if (after < 0) after = 0;
      final page = await client.messages(
        conversationId,
        after: after,
        limit: _floor - 1 - after,
      );
      _floor = after + 1;
      _set(
        _state.copyWith(
          messages: _merge(_state.messages, page.messages),
          loadingOlder: false,
          hasOlder: _floor > 1,
        ),
      );
    } catch (e) {
      _set(_state.copyWith(loadingOlder: false, error: () => e));
    }
  }

  /// Sends a message and adds the stored copy.
  Future<Message> send(
    String text, {
    Map<String, Object?>? metadata,
    List<Attachment> attachments = const [],
  }) async {
    await stopTyping();
    final sent = (await client.send(
      conversationId,
      text,
      metadata: metadata,
      attachments: attachments,
    )).message;
    _add([sent]);
    return sent;
  }

  Future<Message> _keep(Future<Message> f) async {
    final m = await f;
    _add([m]);
    return m;
  }

  Future<Message> edit(int seq, String text) =>
      _keep(client.edit(conversationId, seq, text));
  Future<Message> delete(int seq) => _keep(client.delete(conversationId, seq));

  /// Translates message [seq] into [language] on request.
  Future<Message> translate(int seq, String language) =>
      _keep(client.translate(conversationId, seq, language));

  /// Adds the user's reaction, or takes it back if they already reacted
  /// with [emoji].
  Future<Message> toggleReaction(int seq, String emoji) async {
    final me = await client.currentUser();
    final m = _state.messages.where((m) => m.seq == seq).firstOrNull;
    final mine = m?.reactions[emoji]?.contains(me) ?? false;
    return _keep(
      mine
          ? client.unreact(conversationId, seq, emoji)
          : client.react(conversationId, seq, emoji),
    );
  }

  /// Marks everything loaded as read, when it is not already.
  Future<void> markRead() async {
    final seq = _state.lastSeq;
    final me = await client.currentUser();
    if (seq == 0 || (_state.reads[me] ?? 0) >= seq) return;
    final readSeq = await client.read(conversationId, seq);
    _set(
      _state.copyWith(
        reads: {..._state.reads, me: _max(readSeq, _state.reads[me])},
      ),
    );
  }

  /// Call on every keystroke: tells the others the user is typing at most
  /// every 3 seconds, and that they stopped after 5 seconds without one.
  void typing() {
    final now = DateTime.now();
    final sent = _typingSent;
    if (sent == null || now.difference(sent) > const Duration(seconds: 3)) {
      _typingSent = now;
      client.typing(conversationId).ignore();
    }
    _typingOff?.cancel();
    _typingOff = Timer(const Duration(seconds: 5), () => stopTyping());
  }

  /// Tells the others the user stopped typing (sent only if they were told
  /// it started).
  Future<void> stopTyping() async {
    _typingOff?.cancel();
    if (_typingSent == null) return;
    _typingSent = null;
    try {
      await client.typing(conversationId, typing: false);
    } catch (_) {}
  }

  void _clearTyping(String? user) {
    if (user == null) return;
    _typingTimers.remove(user)?.cancel();
    if (_state.typing.contains(user)) {
      _set(_state.copyWith(typing: {..._state.typing}..remove(user)));
    }
  }

  void _setRead(String user, int seq) {
    if (seq > (_state.reads[user] ?? 0)) {
      _set(_state.copyWith(reads: {..._state.reads, user: seq}));
    }
  }

  /// Applies one event to this conversation (events of other conversations
  /// are ignored).
  void apply(ChatEvent e) {
    if (e.conversationId != conversationId || _disposed) return;
    switch (e) {
      case ChatMessageAdded(:final message):
        _clearTyping(message.sender);
        final s = message.sender;
        if (s != null) _setRead(s, message.seq);
        _add([message]);
      case ChatMessageUpdated(:final message):
        if (_state.messages.any((m) => m.seq == message.seq)) _add([message]);
      case ChatTyping(:final userId, :final typing):
        if (userId == client.userId) return;
        if (typing) {
          _typingTimers.remove(userId)?.cancel();
          _typingTimers[userId] = Timer(typingShow, () => _clearTyping(userId));
          if (!_state.typing.contains(userId)) {
            _set(_state.copyWith(typing: {..._state.typing, userId}));
          }
        } else {
          _clearTyping(userId);
        }
      case ChatRead(:final userId, :final readSeq):
        _setRead(userId, readSeq);
      case ChatConversationChanged(:final conversation):
        _set(
          _state.copyWith(
            conversation: conversation,
            reads: {
              ..._state.reads,
              for (final m in conversation.members)
                m.userId: _max(m.readSeq, _state.reads[m.userId]),
            },
          ),
        );
      case ChatLeft() || ChatDeleted():
        _set(_state.copyWith(closed: true));
    }
  }

  /// Stops listening; the view cannot be started again.
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingOff?.cancel();
    _changes.close();
  }
}
