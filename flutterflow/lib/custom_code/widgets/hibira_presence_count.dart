// Automatic FlutterFlow imports
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/widgets/index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'dart:async';

import 'package:hibira/hibira.dart';

import '/custom_code/actions/hibira_connect.dart';

/// Shows how many people are on a presence channel right now, such as
/// "12 online", and keeps it live. [label] follows the number; set it to an
/// empty string to show the number alone. Your auth endpoint must sign
/// presence channels (see hibiraConnect).
class HibiraPresenceCount extends StatefulWidget {
  const HibiraPresenceCount({
    super.key,
    this.width,
    this.height,
    required this.channelName,
    this.label,
    this.textColor,
    this.dotColor,
    this.fontSize,
    this.onChanged,
  });

  final double? width;
  final double? height;
  final String channelName;
  final String? label;
  final Color? textColor;
  final Color? dotColor;
  final double? fontSize;

  /// Runs with the new member list (JSON) whenever someone joins or leaves.
  final Future Function(List<dynamic> members)? onChanged;

  @override
  State<HibiraPresenceCount> createState() => _HibiraPresenceCountState();
}

class _HibiraPresenceCountState extends State<HibiraPresenceCount> {
  final List<StreamSubscription<Object?>> _subs = [];
  String? _held;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    HibiraFF.current.addListener(_bind);
    _hold();
  }

  @override
  void didUpdateWidget(HibiraPresenceCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelName != widget.channelName) {
      _letGo();
      _hold();
    }
  }

  void _hold() {
    if (!widget.channelName.startsWith('presence-')) {
      debugPrint('Hibira: ${widget.channelName} is not a presence- channel');
      return;
    }
    _held = widget.channelName;
    HibiraFF.hold(widget.channelName);
    _bind();
  }

  void _bind() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final channel = HibiraFF.client?.channel(widget.channelName);
    if (channel is! HibiraPresenceChannel) return;
    void update(Object? _) {
      if (!mounted) return;
      setState(() => _count = channel.count);
      widget.onChanged?.call(HibiraFF.members(widget.channelName));
    }

    _subs
      ..add(channel.memberAdded.listen(update))
      ..add(channel.memberRemoved.listen(update))
      ..add(
        channel.events
            .where((e) => e.name == 'pusher:subscription_succeeded')
            .listen(update),
      );
    if (channel.isSubscribed) update(null);
  }

  void _letGo() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final held = _held;
    if (held != null) HibiraFF.release(held);
    _held = null;
  }

  @override
  void dispose() {
    HibiraFF.current.removeListener(_bind);
    _letGo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final size = widget.fontSize ?? 14;
    final label = widget.label ?? 'online';
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size * 0.6,
            height: size * 0.6,
            decoration: BoxDecoration(
              color: widget.dotColor ?? theme.success,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: size * 0.4),
          Text(
            label.isEmpty ? '$_count' : '$_count $label',
            style: theme.bodyMedium.copyWith(
              color: widget.textColor ?? theme.primaryText,
              fontSize: size,
            ),
          ),
        ],
      ),
    );
  }
}
