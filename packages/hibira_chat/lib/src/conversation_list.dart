import 'dart:async';

import 'client.dart';
import 'events.dart';
import 'models.dart';

/// What a [ChatConversationList] shows.
class ChatConversationListState {
  const ChatConversationListState({
    this.conversations = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  });

  /// Latest activity first, each with `unread`.
  final List<Conversation> conversations;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  /// Unread messages across the loaded conversations.
  int get unread => conversations.fold(0, (n, c) => n + (c.unread ?? 0));
}

/// The user's conversations kept up to date: new messages move a
/// conversation to the top and count as unread, reads clear the count, and
/// conversations the user joins, leaves or that are deleted come and go.
class ChatConversationList {
  ChatConversationList(this.client, {this.pageSize = 30});

  final ChatClient client;
  final int pageSize;

  ChatConversationListState _state = const ChatConversationListState();
  final _changes = StreamController<ChatConversationListState>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  String _next = '';
  bool _disposed = false;

  ChatConversationListState get state => _state;
  Stream<ChatConversationListState> get changes => _changes.stream;

  void _set(ChatConversationListState s) {
    if (_disposed) return;
    _state = s;
    _changes.add(s);
  }

  ChatConversationListState _with({
    List<Conversation>? conversations,
    bool? loading,
    bool? loadingMore,
    Object? Function()? error,
  }) => ChatConversationListState(
    conversations: conversations ?? _state.conversations,
    loading: loading ?? _state.loading,
    loadingMore: loadingMore ?? _state.loadingMore,
    hasMore: _next.isNotEmpty,
    error: error == null ? _state.error : error(),
  );

  void start() {
    if (_subs.isNotEmpty || _disposed) return;
    _subs.add(client.events.listen(apply));
    _subs.add(client.live.listen((_) => refresh()));
    refresh();
  }

  /// Loads the first page again.
  Future<void> refresh() async {
    try {
      final page = await client.conversations(limit: pageSize);
      _next = page.next;
      _set(
        _with(
          conversations: page.conversations,
          loading: false,
          error: () => null,
        ),
      );
    } catch (e) {
      _set(_with(loading: false, error: () => e));
    }
  }

  /// Loads the next page, if there is one.
  Future<void> loadMore() async {
    if (_next.isEmpty || _state.loadingMore) return;
    _set(_with(loadingMore: true));
    try {
      final page = await client.conversations(limit: pageSize, before: _next);
      _next = page.next;
      final have = {for (final c in _state.conversations) c.id};
      _set(
        _with(
          conversations: [
            ..._state.conversations,
            ...page.conversations.where((c) => !have.contains(c.id)),
          ],
          loadingMore: false,
        ),
      );
    } catch (e) {
      _set(_with(loadingMore: false, error: () => e));
    }
  }

  /// Applies one event to the list.
  void apply(ChatEvent e) {
    if (_disposed) return;
    final me = client.userId;
    final list = _state.conversations;
    switch (e) {
      case ChatMessageAdded(:final message):
        final i = list.indexWhere((c) => c.id == e.conversationId);
        if (i < 0) {
          refresh();
          return;
        }
        final c = list[i];
        final unread = message.sender == me
            ? 0
            : (c.unread ?? 0) + (message.isSystem ? 0 : 1);
        final moved = c.copyWith(
          lastSeq: message.seq > c.lastSeq ? message.seq : c.lastSeq,
          updatedAt: message.createdAt,
          unread: unread,
        );
        _set(
          _with(
            conversations: [
              moved,
              ...list.where((x) => x.id != e.conversationId),
            ],
          ),
        );
      case ChatRead(:final userId, :final readSeq):
        if (userId != me) return;
        _set(
          _with(
            conversations: [
              for (final c in list)
                c.id == e.conversationId && readSeq >= c.lastSeq
                    ? c.copyWith(unread: 0)
                    : c,
            ],
          ),
        );
      case ChatConversationChanged(:final conversation):
        final i = list.indexWhere((c) => c.id == conversation.id);
        final updated = conversation.copyWith(
          unread: i < 0 ? 0 : (list[i].unread ?? 0),
        );
        _set(
          _with(
            conversations: i < 0
                ? [updated, ...list]
                : [for (final c in list) c.id == updated.id ? updated : c],
          ),
        );
      case ChatLeft() || ChatDeleted():
        _set(
          _with(
            conversations: [
              for (final c in list)
                if (c.id != e.conversationId) c,
            ],
          ),
        );
      case ChatMessageUpdated() || ChatTyping():
        break;
    }
  }

  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _changes.close();
  }
}
