import 'package:flutter/widgets.dart';

import 'notification.dart';

/// The strings of [NotificationBell] and [NotificationInbox]. Built in:
/// English, Traditional and Simplified Chinese, Japanese, Korean, Thai and
/// Vietnamese. Use [InboxLabels.of] for the app's locale, or [copyWith] to
/// change single strings.
class InboxLabels {
  const InboxLabels({
    required this.title,
    required this.unreadCount,
    required this.tabInbox,
    required this.tabUnread,
    required this.tabArchived,
    required this.markAllRead,
    required this.markRead,
    required this.markUnread,
    required this.archive,
    required this.unarchive,
    required this.emptyInbox,
    required this.emptyUnread,
    required this.emptyArchived,
    required this.loadMore,
    required this.error,
    required this.retry,
  });

  final String title;

  /// "{count} unread", for the bell's accessibility label.
  final String unreadCount;
  final String tabInbox;
  final String tabUnread;
  final String tabArchived;
  final String markAllRead;
  final String markRead;
  final String markUnread;
  final String archive;
  final String unarchive;
  final String emptyInbox;
  final String emptyUnread;
  final String emptyArchived;
  final String loadMore;
  final String error;
  final String retry;

  String tab(InboxStatus s) => switch (s) {
    InboxStatus.inbox => tabInbox,
    InboxStatus.unread => tabUnread,
    InboxStatus.archived => tabArchived,
    InboxStatus.read => markRead,
    InboxStatus.all => title,
  };

  String empty(InboxStatus s) => switch (s) {
    InboxStatus.unread => emptyUnread,
    InboxStatus.archived => emptyArchived,
    _ => emptyInbox,
  };

  String unread(int count) => unreadCount.replaceAll('{count}', '$count');

  static const en = InboxLabels(
    title: 'Notifications',
    unreadCount: '{count} unread',
    tabInbox: 'Inbox',
    tabUnread: 'Unread',
    tabArchived: 'Archived',
    markAllRead: 'Mark all as read',
    markRead: 'Mark as read',
    markUnread: 'Mark as unread',
    archive: 'Archive',
    unarchive: 'Move to inbox',
    emptyInbox: 'You are all caught up.',
    emptyUnread: 'No unread notifications.',
    emptyArchived: 'Nothing archived.',
    loadMore: 'Show older',
    error: 'Could not load notifications.',
    retry: 'Try again',
  );

  static const zhTW = InboxLabels(
    title: '通知',
    unreadCount: '{count} 則未讀',
    tabInbox: '收件匣',
    tabUnread: '未讀',
    tabArchived: '已封存',
    markAllRead: '全部標為已讀',
    markRead: '標為已讀',
    markUnread: '標為未讀',
    archive: '封存',
    unarchive: '移回收件匣',
    emptyInbox: '目前沒有新通知。',
    emptyUnread: '沒有未讀通知。',
    emptyArchived: '沒有封存的通知。',
    loadMore: '顯示較舊的通知',
    error: '無法載入通知。',
    retry: '重試',
  );

  static const zhCN = InboxLabels(
    title: '通知',
    unreadCount: '{count} 条未读',
    tabInbox: '收件箱',
    tabUnread: '未读',
    tabArchived: '已归档',
    markAllRead: '全部标为已读',
    markRead: '标为已读',
    markUnread: '标为未读',
    archive: '归档',
    unarchive: '移回收件箱',
    emptyInbox: '暂时没有新通知。',
    emptyUnread: '没有未读通知。',
    emptyArchived: '没有归档的通知。',
    loadMore: '显示更早的通知',
    error: '无法加载通知。',
    retry: '重试',
  );

  static const ja = InboxLabels(
    title: '通知',
    unreadCount: '未読 {count} 件',
    tabInbox: '受信箱',
    tabUnread: '未読',
    tabArchived: 'アーカイブ',
    markAllRead: 'すべて既読にする',
    markRead: '既読にする',
    markUnread: '未読にする',
    archive: 'アーカイブ',
    unarchive: '受信箱に戻す',
    emptyInbox: '新しい通知はありません。',
    emptyUnread: '未読の通知はありません。',
    emptyArchived: 'アーカイブした通知はありません。',
    loadMore: '以前の通知を表示',
    error: '通知を読み込めませんでした。',
    retry: '再試行',
  );

  static const ko = InboxLabels(
    title: '알림',
    unreadCount: '읽지 않음 {count}개',
    tabInbox: '받은 알림',
    tabUnread: '읽지 않음',
    tabArchived: '보관됨',
    markAllRead: '모두 읽음으로 표시',
    markRead: '읽음으로 표시',
    markUnread: '읽지 않음으로 표시',
    archive: '보관',
    unarchive: '받은 알림으로 이동',
    emptyInbox: '새 알림이 없습니다.',
    emptyUnread: '읽지 않은 알림이 없습니다.',
    emptyArchived: '보관된 알림이 없습니다.',
    loadMore: '이전 알림 보기',
    error: '알림을 불러오지 못했습니다.',
    retry: '다시 시도',
  );

  static const th = InboxLabels(
    title: 'การแจ้งเตือน',
    unreadCount: 'ยังไม่อ่าน {count} รายการ',
    tabInbox: 'กล่องข้อความ',
    tabUnread: 'ยังไม่อ่าน',
    tabArchived: 'เก็บถาวร',
    markAllRead: 'ทำเครื่องหมายว่าอ่านทั้งหมด',
    markRead: 'ทำเครื่องหมายว่าอ่านแล้ว',
    markUnread: 'ทำเครื่องหมายว่ายังไม่อ่าน',
    archive: 'เก็บถาวร',
    unarchive: 'ย้ายกลับกล่องข้อความ',
    emptyInbox: 'ไม่มีการแจ้งเตือนใหม่',
    emptyUnread: 'ไม่มีการแจ้งเตือนที่ยังไม่อ่าน',
    emptyArchived: 'ไม่มีรายการที่เก็บถาวร',
    loadMore: 'แสดงรายการก่อนหน้า',
    error: 'โหลดการแจ้งเตือนไม่ได้',
    retry: 'ลองอีกครั้ง',
  );

  static const vi = InboxLabels(
    title: 'Thông báo',
    unreadCount: '{count} chưa đọc',
    tabInbox: 'Hộp thư',
    tabUnread: 'Chưa đọc',
    tabArchived: 'Đã lưu trữ',
    markAllRead: 'Đánh dấu tất cả là đã đọc',
    markRead: 'Đánh dấu đã đọc',
    markUnread: 'Đánh dấu chưa đọc',
    archive: 'Lưu trữ',
    unarchive: 'Chuyển về hộp thư',
    emptyInbox: 'Bạn đã xem hết thông báo.',
    emptyUnread: 'Không có thông báo chưa đọc.',
    emptyArchived: 'Chưa có thông báo lưu trữ.',
    loadMore: 'Xem thông báo cũ hơn',
    error: 'Không tải được thông báo.',
    retry: 'Thử lại',
  );

  /// The labels for [locale], by language and script, falling back to English.
  static InboxLabels forLocale(Locale locale) {
    switch (locale.languageCode) {
      case 'zh':
        final hans =
            locale.scriptCode == 'Hans' ||
            (locale.scriptCode == null &&
                const {'CN', 'SG'}.contains(locale.countryCode));
        return hans ? zhCN : zhTW;
      case 'ja':
        return ja;
      case 'ko':
        return ko;
      case 'th':
        return th;
      case 'vi':
        return vi;
      default:
        return en;
    }
  }

  /// The labels for the app's current locale.
  static InboxLabels of(BuildContext context) =>
      forLocale(Localizations.maybeLocaleOf(context) ?? const Locale('en'));

  InboxLabels copyWith({
    String? title,
    String? unreadCount,
    String? tabInbox,
    String? tabUnread,
    String? tabArchived,
    String? markAllRead,
    String? markRead,
    String? markUnread,
    String? archive,
    String? unarchive,
    String? emptyInbox,
    String? emptyUnread,
    String? emptyArchived,
    String? loadMore,
    String? error,
    String? retry,
  }) => InboxLabels(
    title: title ?? this.title,
    unreadCount: unreadCount ?? this.unreadCount,
    tabInbox: tabInbox ?? this.tabInbox,
    tabUnread: tabUnread ?? this.tabUnread,
    tabArchived: tabArchived ?? this.tabArchived,
    markAllRead: markAllRead ?? this.markAllRead,
    markRead: markRead ?? this.markRead,
    markUnread: markUnread ?? this.markUnread,
    archive: archive ?? this.archive,
    unarchive: unarchive ?? this.unarchive,
    emptyInbox: emptyInbox ?? this.emptyInbox,
    emptyUnread: emptyUnread ?? this.emptyUnread,
    emptyArchived: emptyArchived ?? this.emptyArchived,
    loadMore: loadMore ?? this.loadMore,
    error: error ?? this.error,
    retry: retry ?? this.retry,
  );
}
