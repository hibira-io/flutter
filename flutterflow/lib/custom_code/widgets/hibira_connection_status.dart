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

import 'package:hibira/hibira.dart';

import '/custom_code/actions/hibira_connect.dart';

/// A small dot (and optional text) that shows whether the app is connected
/// to Hibira: green when connected, amber while connecting, red when
/// offline. Handy on chat screens and dashboards.
class HibiraConnectionStatus extends StatelessWidget {
  const HibiraConnectionStatus({
    super.key,
    this.width,
    this.height,
    this.showText,
    this.connectedText,
    this.connectingText,
    this.offlineText,
    this.fontSize,
  });

  final double? width;
  final double? height;
  final bool? showText;
  final String? connectedText;
  final String? connectingText;
  final String? offlineText;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final size = fontSize ?? 14;
    return SizedBox(
      width: width,
      height: height,
      child: ValueListenableBuilder<HibiraConnectionState>(
        valueListenable: HibiraFF.state,
        builder: (context, state, _) {
          final (Color color, String text) = switch (state) {
            HibiraConnectionState.connected => (
              theme.success,
              connectedText ?? 'Live',
            ),
            HibiraConnectionState.connecting ||
            HibiraConnectionState.reconnecting => (
              theme.warning,
              connectingText ?? 'Connecting',
            ),
            HibiraConnectionState.disconnected => (
              theme.error,
              offlineText ?? 'Offline',
            ),
          };
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size * 0.6,
                height: size * 0.6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (showText ?? true) ...[
                SizedBox(width: size * 0.4),
                Text(
                  text,
                  style: theme.bodyMedium.copyWith(
                    color: theme.secondaryText,
                    fontSize: size,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
