/// One stored notification of the signed-in user.
class InboxNotification {
  const InboxNotification({
    required this.id,
    required this.title,
    required this.createdAt,
    this.body,
    this.url,
    this.icon,
    this.category,
    this.data,
    this.readAt,
    this.archivedAt,
  });

  factory InboxNotification.fromJson(Map<String, Object?> json) {
    DateTime? time(Object? v) => v is String ? DateTime.tryParse(v) : null;
    final data = json['data'];
    return InboxNotification(
      id: json['id']! as String,
      title: json['title'] as String? ?? '',
      body: json['body'] as String?,
      url: json['url'] as String?,
      icon: json['icon'] as String?,
      category: json['category'] as String?,
      data: data is Map ? data.cast<String, Object?>() : null,
      createdAt: time(json['created_at']) ?? DateTime.now(),
      readAt: time(json['read_at']),
      archivedAt: time(json['archived_at']),
    );
  }

  final String id;
  final String title;
  final String? body;

  /// Where the notification leads: an http(s) URL or a path on your site.
  final String? url;
  final String? icon;
  final String? category;

  /// The object your server sent as `data`.
  final Map<String, Object?>? data;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? archivedAt;

  bool get isRead => readAt != null;
  bool get isArchived => archivedAt != null;

  /// Unread and not archived: what the bell counts.
  bool get isUnread => readAt == null && archivedAt == null;

  InboxNotification copyWith({
    DateTime? Function()? readAt,
    DateTime? Function()? archivedAt,
  }) => InboxNotification(
    id: id,
    title: title,
    body: body,
    url: url,
    icon: icon,
    category: category,
    data: data,
    createdAt: createdAt,
    readAt: readAt != null ? readAt() : this.readAt,
    archivedAt: archivedAt != null ? archivedAt() : this.archivedAt,
  );
}

/// Which notifications a list shows.
enum InboxStatus {
  /// Everything not archived.
  inbox(''),
  unread('unread'),
  read('read'),
  archived('archived'),
  all('all');

  const InboxStatus(this.query);

  /// The value of the API's `status` parameter.
  final String query;

  bool matches(InboxNotification n) => switch (this) {
    InboxStatus.inbox => !n.isArchived,
    InboxStatus.unread => n.isUnread,
    InboxStatus.read => n.isRead && !n.isArchived,
    InboxStatus.archived => n.isArchived,
    InboxStatus.all => true,
  };
}
