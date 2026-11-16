import 'models.dart';

/// A Chat API event, sent to each member concerned on their
/// `#server-to-user-<id>` channel.
sealed class ChatEvent {
  const ChatEvent(this.conversationId);

  final String conversationId;

  /// The event names the Chat API sends.
  static const names = [
    'chat.message',
    'chat.message_updated',
    'chat.typing',
    'chat.read',
    'chat.conversation',
    'chat.left',
    'chat.deleted',
  ];

  /// Parses an event by name and its decoded data; null when it is not a
  /// chat event.
  static ChatEvent? parse(String name, Object? data) {
    if (data is! Map) return null;
    final d = data.cast<String, Object?>();
    final id = '${d['conversation_id'] ?? ''}';
    Map<String, Object?> obj(String k) =>
        d[k] is Map ? (d[k] as Map).cast<String, Object?>() : const {};
    final ChatEvent? e = switch (name) {
      'chat.message' => ChatMessageAdded(id, Message.fromJson(obj('message'))),
      'chat.message_updated' => ChatMessageUpdated(
        id,
        Message.fromJson(obj('message')),
      ),
      'chat.typing' => ChatTyping(
        id,
        '${d['user_id'] ?? ''}',
        d['typing'] != false,
      ),
      'chat.read' => ChatRead(
        id,
        '${d['user_id'] ?? ''}',
        d['read_seq'] is num ? (d['read_seq'] as num).toInt() : 0,
      ),
      'chat.conversation' => ChatConversationChanged(
        Conversation.fromJson(obj('conversation')),
      ),
      'chat.left' => ChatLeft(id),
      'chat.deleted' => ChatDeleted(id),
      _ => null,
    };
    if (e == null || e.conversationId.isEmpty) return null;
    return e;
  }
}

/// `chat.message`: a new message.
class ChatMessageAdded extends ChatEvent {
  const ChatMessageAdded(super.conversationId, this.message);
  final Message message;
}

/// `chat.message_updated`: a message was edited, deleted or its reactions
/// changed.
class ChatMessageUpdated extends ChatEvent {
  const ChatMessageUpdated(super.conversationId, this.message);
  final Message message;
}

/// `chat.typing`: another member started or stopped typing.
class ChatTyping extends ChatEvent {
  const ChatTyping(super.conversationId, this.userId, this.typing);
  final String userId;
  final bool typing;
}

/// `chat.read`: a member's read_seq moved forward.
class ChatRead extends ChatEvent {
  const ChatRead(super.conversationId, this.userId, this.readSeq);
  final String userId;
  final int readSeq;
}

/// `chat.conversation`: the conversation was created or changed, or a
/// member was added.
class ChatConversationChanged extends ChatEvent {
  ChatConversationChanged(this.conversation) : super(conversation.id);
  final Conversation conversation;
}

/// `chat.left`: the user was removed from the conversation.
class ChatLeft extends ChatEvent {
  const ChatLeft(super.conversationId);
}

/// `chat.deleted`: the conversation was deleted.
class ChatDeleted extends ChatEvent {
  const ChatDeleted(super.conversationId);
}
