Map<String, Object?> _map(Object? v) =>
    v is Map ? v.cast<String, Object?>() : const {};
List<Object?> _list(Object? v) => v is List ? v : const [];
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

/// A member of a conversation and how far they have read.
class Member {
  const Member({required this.userId, this.readSeq = 0, this.role});

  factory Member.fromJson(Map<String, Object?> j) => Member(
    userId: '${j['user_id'] ?? ''}',
    readSeq: _int(j['read_seq']),
    role: _str(j['role']),
  );

  final String userId;
  final int readSeq;
  final String? role;
}

/// A conversation of the Chat API.
class Conversation {
  const Conversation({
    required this.id,
    this.name,
    this.metadata = const {},
    this.members = const [],
    this.lastSeq = 0,
    this.createdAt,
    this.updatedAt,
    this.unread,
    this.raw = const {},
  });

  factory Conversation.fromJson(Map<String, Object?> j) => Conversation(
    id: '${j['id'] ?? ''}',
    name: _str(j['name']),
    metadata: _map(j['metadata']),
    members: [for (final m in _list(j['members'])) Member.fromJson(_map(m))],
    lastSeq: _int(j['last_seq']),
    createdAt: _str(j['created_at']),
    updatedAt: _str(j['updated_at']),
    unread: j['unread'] == null ? null : _int(j['unread']),
    raw: j,
  );

  final String id;
  final String? name;
  final Map<String, Object?> metadata;
  final List<Member> members;
  final int lastSeq;
  final String? createdAt;
  final String? updatedAt;

  /// In conversation lists: messages after the user's read_seq that are not
  /// system messages.
  final int? unread;

  /// The whole object as the API sent it.
  final Map<String, Object?> raw;

  /// How far [userId] has read, or 0.
  int readSeq(String userId) {
    for (final m in members) {
      if (m.userId == userId) return m.readSeq;
    }
    return 0;
  }

  Conversation copyWith({int? lastSeq, String? updatedAt, int? unread}) =>
      Conversation(
        id: id,
        name: name,
        metadata: metadata,
        members: members,
        lastSeq: lastSeq ?? this.lastSeq,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        unread: unread ?? this.unread,
        raw: raw,
      );
}

/// A file attached to a message. [url] downloads it for an hour.
class Attachment {
  const Attachment({
    required this.id,
    required this.name,
    required this.contentType,
    this.size = 0,
    this.url,
  });

  factory Attachment.fromJson(Map<String, Object?> j) => Attachment(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    contentType: '${j['content_type'] ?? 'application/octet-stream'}',
    size: _int(j['size']),
    url: _str(j['url']),
  );

  final String id;
  final String name;
  final String contentType;
  final int size;
  final String? url;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'content_type': contentType,
  };
}

/// A stored message. A changed message keeps its [seq].
class Message {
  const Message({
    required this.id,
    required this.seq,
    this.sender,
    this.name,
    this.kind = 'text',
    this.text = '',
    this.metadata = const {},
    this.createdAt,
    this.editedAt,
    this.deletedAt,
    this.reactions = const {},
    this.attachments = const [],
    this.visibleTo = const [],
    this.language,
    this.translations = const {},
    this.raw = const {},
  });

  factory Message.fromJson(Map<String, Object?> j) => Message(
    id: '${j['id'] ?? ''}',
    seq: _int(j['seq']),
    sender: _str(j['sender']),
    name: _str(j['name']),
    kind: _str(j['kind']) ?? 'text',
    text: '${j['text'] ?? ''}',
    metadata: _map(j['metadata']),
    createdAt: _str(j['created_at']),
    editedAt: _str(j['edited_at']),
    deletedAt: _str(j['deleted_at']),
    reactions: {
      for (final e in _map(j['reactions']).entries)
        e.key: [for (final u in _list(e.value)) '$u'],
    },
    attachments: [
      for (final a in _list(j['attachments'])) Attachment.fromJson(_map(a)),
    ],
    visibleTo: [for (final r in _list(j['visible_to'])) '$r'],
    language: _str(j['language']),
    translations: {
      for (final e in _map(j['translations']).entries) e.key: '${e.value}',
    },
    raw: j,
  );

  final String id;
  final int seq;

  /// The sender's user ID; null for system messages.
  final String? sender;
  final String? name;

  /// `text`, or `system` for messages your server posts about the
  /// conversation.
  final String kind;
  final String text;
  final Map<String, Object?> metadata;
  final String? createdAt;
  final String? editedAt;
  final String? deletedAt;

  /// Each emoji and the members who reacted, in order.
  final Map<String, List<String>> reactions;
  final List<Attachment> attachments;

  /// The roles this message is limited to (internal notes), if any.
  final List<String> visibleTo;

  /// The language [text] was written in, when the app sets users' languages.
  final String? language;

  /// [text] translated, by BCP 47 language tag.
  final Map<String, String> translations;
  final Map<String, Object?> raw;

  /// The text to show a reader of [lang]: its translation when there is one,
  /// else [text].
  String textFor(String? lang) {
    if (lang == null || lang.isEmpty) return text;
    return translations[lang] ?? text;
  }

  bool get isSystem => kind == 'system';
  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
}

/// A message someone reported.
class Report {
  const Report({
    required this.id,
    required this.conversationId,
    required this.seq,
    required this.reportedBy,
    required this.reason,
    this.message,
  });

  factory Report.fromJson(Map<String, Object?> j) => Report(
    id: '${j['id'] ?? ''}',
    conversationId: '${j['conversation_id'] ?? ''}',
    seq: _int(j['seq']),
    reportedBy: '${j['reported_by'] ?? ''}',
    reason: '${j['reason'] ?? ''}',
    message: j['message'] is Map ? Message.fromJson(_map(j['message'])) : null,
  );

  final String id;
  final String conversationId;
  final int seq;
  final String reportedBy;
  final String reason;
  final Message? message;
}

/// A page of the user's conversations, latest activity first. Pass [next]
/// as `before` for the next page.
class ConversationPage {
  const ConversationPage(this.conversations, this.next);
  final List<Conversation> conversations;
  final String next;
}

/// Messages, oldest first, and the conversation's newest sequence number.
class MessagePage {
  const MessagePage(this.messages, this.lastSeq);
  final List<Message> messages;
  final int lastSeq;
}

/// Search results, newest first. Pass [next] as `before` for more.
class SearchPage {
  const SearchPage(this.messages, this.next);
  final List<Message> messages;
  final String next;
}

/// The answer to a send: the stored message, and how many members were
/// pushed.
class SendResult {
  const SendResult(this.message, {this.pushedUsers, this.pushError});
  final Message message;
  final int? pushedUsers;
  final String? pushError;
}
