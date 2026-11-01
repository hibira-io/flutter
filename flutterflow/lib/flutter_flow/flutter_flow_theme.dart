// Stand-in for the file FlutterFlow generates. Not pasted into FlutterFlow.
import 'package:flutter/material.dart';

class FlutterFlowTheme {
  FlutterFlowTheme._(this._theme);

  final ThemeData _theme;

  static FlutterFlowTheme of(BuildContext context) =>
      FlutterFlowTheme._(Theme.of(context));

  Color get primaryText => _theme.colorScheme.onSurface;
  Color get secondaryText => _theme.colorScheme.onSurfaceVariant;
  Color get success => const Color(0xFF16A34A);
  Color get warning => const Color(0xFFF59E0B);
  Color get error => _theme.colorScheme.error;
  TextStyle get bodyMedium => _theme.textTheme.bodyMedium ?? const TextStyle();
}
