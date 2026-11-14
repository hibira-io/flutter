import 'dart:async';

// See main.dart: material_ui needs Flutter 3.47 and we support 3.32.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:hibira/hibira.dart';

import 'main.dart' show appKey, authEndpoint, host;

/// A chat room on one presence channel. Messages and "typing…" are client
/// events: they go from this phone to everyone in the room over the open
/// socket, with no polling and no request to your server per message.
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  late final HibiraClient _client;
  late final HibiraPresenceChannel _room;
  final _subs = <StreamSubscription<Object?>>[];
  final _input = TextEditingController();
  final _messages = <({String from, String text})>[];
  String? _typing;
  Timer? _typingTimeout;
  DateTime _lastTyping = DateTime(0);

  @override
  void initState() {
    super.initState();
    // One socket for the whole app. Your backend signs who the user is.
    _client = HibiraClient(
      appKey,
      options: HibiraOptions(host: host, authEndpoint: Uri.parse(authEndpoint)),
    );
    _client.connect();
    _room = _client.subscribePresence('presence-chat');
    _subs
      ..add(
        _room.on('client-message').listen((e) {
          final data = e.data as Map;
          setState(() {
            _messages.add((from: _name(e.userId), text: '${data['text']}'));
            _typing = null;
          });
        }),
      )
      ..add(
        _room.on('client-typing').listen((e) {
          setState(() => _typing = _name(e.userId));
          _typingTimeout?.cancel();
          _typingTimeout = Timer(
            const Duration(seconds: 3),
            () => setState(() => _typing = null),
          );
        }),
      )
      ..add(_room.memberAdded.listen((_) => setState(() {})))
      ..add(_room.memberRemoved.listen((_) => setState(() {})));
    _room.whenSubscribed.then((_) => setState(() {}), onError: (_) {});
  }

  String _name(String? userId) {
    final info = _room.member(userId ?? '')?.info;
    return info is Map ? '${info['name']}' : userId ?? '?';
  }

  void _onChanged(String _) {
    // At most one typing event every 2 seconds.
    final now = DateTime.now();
    if (now.difference(_lastTyping).inSeconds < 2) return;
    _lastTyping = now;
    _room.trigger('client-typing', {});
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    // Client events are not echoed back to the sender, so add it here.
    _room.trigger('client-message', {'text': text});
    setState(() => _messages.add((from: _name(_room.myId), text: text)));
    _input.clear();
    _lastTyping = DateTime(0);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _typingTimeout?.cancel();
    _client.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = _name(_room.myId);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _room.isSubscribed ? '${_room.count} in the room' : 'Joining…',
            style: theme.textTheme.titleMedium,
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView(
              children: [
                for (final m in _messages)
                  Align(
                    alignment: m.from == me
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Card(
                      color: m.from == me
                          ? theme.colorScheme.primaryContainer
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text('${m.from}: ${m.text}'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 24,
            child: _typing == null
                ? null
                : Text('$_typing is typing…', style: theme.textTheme.bodySmall),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  decoration: const InputDecoration(labelText: 'Message'),
                  onChanged: _onChanged,
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _send, child: const Text('Send')),
            ],
          ),
        ],
      ),
    );
  }
}
