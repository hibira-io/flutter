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

/// Listens to a channel while this widget is on screen and runs [onEvent]
/// with each event's data as JSON. Leave [eventName] empty for every event.
/// It draws nothing: drop it anywhere on the page, for example in a Stack.
class HibiraEventListener extends StatefulWidget {
  const HibiraEventListener({
    super.key,
    this.width,
    this.height,
    required this.channelName,
    this.eventName,
    required this.onEvent,
  });

  final double? width;
  final double? height;
  final String channelName;
  final String? eventName;
  final Future Function(dynamic data) onEvent;

  @override
  State<HibiraEventListener> createState() => _HibiraEventListenerState();
}

class _HibiraEventListenerState extends State<HibiraEventListener> {
  StreamSubscription<HibiraEvent>? _sub;
  String? _held;

  @override
  void initState() {
    super.initState();
    HibiraFF.current.addListener(_bind);
    _hold();
  }

  @override
  void didUpdateWidget(HibiraEventListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelName != widget.channelName ||
        oldWidget.eventName != widget.eventName) {
      _letGo();
      _hold();
    }
  }

  void _hold() {
    _held = widget.channelName;
    HibiraFF.hold(widget.channelName);
    _bind();
  }

  void _bind() {
    _sub?.cancel();
    _sub = null;
    final channel = HibiraFF.client?.channel(widget.channelName);
    if (channel == null) return;
    _sub = HibiraFF.eventsOf(
      channel,
      widget.eventName ?? '',
    ).listen((e) => widget.onEvent(e.data));
  }

  void _letGo() {
    _sub?.cancel();
    _sub = null;
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
  Widget build(BuildContext context) =>
      SizedBox(width: widget.width ?? 0, height: widget.height ?? 0);
}
