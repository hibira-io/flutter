// Automatic FlutterFlow imports
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/actions/index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import '/custom_code/actions/hibira_connect.dart';

/// Sends a client event to everyone else on a private or presence channel,
/// such as typing indicators or cursor moves. [eventName] must start with
/// `client-`, client events must be on for the app in the Hibira portal, and
/// the app must be subscribed to the channel (a HibiraEventListener or
/// hibiraSubscribe on it). Returns false when the event was not sent.
Future<bool> hibiraTrigger(
  String channelName,
  String eventName,
  dynamic data,
) async {
  final client = HibiraFF.client;
  if (client == null) return false;
  try {
    return client.trigger(channelName, eventName, data);
  } on ArgumentError catch (e) {
    debugPrint('Hibira: $e');
    return false;
  }
}
