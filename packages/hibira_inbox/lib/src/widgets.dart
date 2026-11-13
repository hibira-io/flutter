// material_ui replaces this library from Flutter 3.47, but it does not exist
// before 3.47 and we still support Flutter 3.32.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'inbox.dart';
import 'labels.dart';
import 'notification.dart';

/// What happens when the user taps a notification, e.g. open `url` or
/// navigate with `data`. The notification is marked read first.
typedef NotificationSelected = void Function(InboxNotification notification);

/// A bell with the unread count. Tapping it opens [NotificationInbox] in a
/// bottom sheet, or calls [onPressed] instead (to push a page of your own).
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.inbox,
    this.onSelect,
    this.onPressed,
    this.labels,
    this.tabs = NotificationInbox.defaultTabs,
    this.icon = const Icon(Icons.notifications_none_rounded),
  });

  final HibiraInbox inbox;
  final NotificationSelected? onSelect;
  final VoidCallback? onPressed;
  final InboxLabels? labels;
  final List<InboxStatus> tabs;
  final Widget icon;

  /// Opens the inbox in a modal bottom sheet.
  static Future<void> showSheet(
    BuildContext context, {
    required HibiraInbox inbox,
    NotificationSelected? onSelect,
    InboxLabels? labels,
    List<InboxStatus> tabs = NotificationInbox.defaultTabs,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheet) => FractionallySizedBox(
      heightFactor: 0.85,
      child: NotificationInbox(
        inbox: inbox,
        labels: labels,
        tabs: tabs,
        onSelect: (n) {
          Navigator.of(sheet).pop();
          onSelect?.call(n);
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = labels ?? InboxLabels.of(context);
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) {
        final count = inbox.unread;
        return IconButton(
          tooltip: count > 0 ? '${t.title}, ${t.unread(count)}' : t.title,
          onPressed:
              onPressed ??
              () => showSheet(
                context,
                inbox: inbox,
                onSelect: onSelect,
                labels: labels,
                tabs: tabs,
              ),
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text(count > 99 ? '99+' : '$count'),
            child: icon,
          ),
        );
      },
    );
  }
}

/// The inbox: a header with "mark all as read", tabs, and the list with
/// pull to refresh and "show older".
class NotificationInbox extends StatelessWidget {
  const NotificationInbox({
    super.key,
    required this.inbox,
    this.onSelect,
    this.labels,
    this.tabs = defaultTabs,
    this.showHeader = true,
  });

  static const defaultTabs = [
    InboxStatus.inbox,
    InboxStatus.unread,
    InboxStatus.archived,
  ];

  final HibiraInbox inbox;
  final NotificationSelected? onSelect;
  final InboxLabels? labels;
  final List<InboxStatus> tabs;

  /// Show the title and "mark all as read" (turn off inside your own AppBar).
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final t = labels ?? InboxLabels.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) {
        final items = inbox.items;
        Widget body;
        if (inbox.error != null && items.isEmpty) {
          body = _State(
            icon: Icons.cloud_off_rounded,
            text: t.error,
            action: OutlinedButton(
              onPressed: inbox.refresh,
              child: Text(t.retry),
            ),
          );
        } else if (!inbox.ready || (inbox.loading && items.isEmpty)) {
          body = const Center(child: CircularProgressIndicator());
        } else if (items.isEmpty) {
          body = _State(
            icon: Icons.notifications_none_rounded,
            text: t.empty(inbox.status),
          );
        } else {
          body = ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length + (inbox.hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == items.length) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: inbox.loadingMore
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: inbox.loadMore,
                            child: Text(t.loadMore),
                          ),
                  ),
                );
              }
              return NotificationTile(
                key: ValueKey(items[i].id),
                notification: items[i],
                inbox: inbox,
                labels: t,
                onSelect: onSelect,
              );
            },
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(t.title, style: theme.textTheme.titleLarge),
                    ),
                    if (inbox.unread > 0)
                      IconButton(
                        tooltip: t.markAllRead,
                        icon: const Icon(Icons.done_all_rounded),
                        onPressed: () => inbox.markAllRead().catchError((_) {}),
                      ),
                  ],
                ),
              ),
            if (tabs.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    for (final s in tabs)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            s == InboxStatus.inbox && inbox.unread > 0
                                ? '${t.tab(s)}  ${inbox.unread > 99 ? '99+' : inbox.unread}'
                                : t.tab(s),
                          ),
                          selected: inbox.status == s,
                          onSelected: (_) => inbox.setStatus(s),
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: RefreshIndicator(onRefresh: inbox.refresh, child: body),
            ),
          ],
        );
      },
    );
  }
}

/// One row of [NotificationInbox]; use it in a list of your own.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.inbox,
    this.labels,
    this.onSelect,
  });

  final InboxNotification notification;
  final HibiraInbox inbox;
  final InboxLabels? labels;
  final NotificationSelected? onSelect;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final t = labels ?? InboxLabels.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = n.isUnread;
    final initial = (n.category ?? n.title).trim();
    Widget action(
      IconData icon,
      String tip,
      Future<void> Function(List<String>) run,
    ) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      icon: Icon(icon),
      onPressed: () => run([n.id]).catchError((_) {}),
    );
    return Material(
      color: unread
          ? scheme.primaryContainer.withValues(alpha: 0.25)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (unread) inbox.markRead([n.id]).catchError((_) {});
          onSelect?.call(n);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 10,
                child: unread
                    ? Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: CircleAvatar(
                          radius: 3.5,
                          backgroundColor: scheme.primary,
                        ),
                      )
                    : null,
              ),
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.surfaceContainerHighest,
                foregroundImage: n.icon != null ? NetworkImage(n.icon!) : null,
                child: Text(
                  initial.isEmpty
                      ? '?'
                      : initial.characters.first.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (n.body != null && n.body!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          n.body!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        ago(n.createdAt, MaterialLocalizations.of(context)),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (n.isArchived)
                action(Icons.unarchive_outlined, t.unarchive, inbox.unarchive)
              else ...[
                unread
                    ? action(Icons.done_all_rounded, t.markRead, inbox.markRead)
                    : action(
                        Icons.mark_email_unread_outlined,
                        t.markUnread,
                        inbox.markUnread,
                      ),
                action(Icons.archive_outlined, t.archive, inbox.archive),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A short age: "now", "5m", "3h", "2d", then the date.
@visibleForTesting
String ago(DateTime at, MaterialLocalizations l10n, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return l10n.formatShortDate(at.toLocal());
}

class _State extends StatelessWidget {
  const _State({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // A scrollable, so pull to refresh works on an empty list too.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 36, color: muted),
                  const SizedBox(height: 12),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                  if (action != null) ...[const SizedBox(height: 12), action!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
