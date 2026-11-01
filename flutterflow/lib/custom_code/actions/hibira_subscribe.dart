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

/// Runs [onEvent] each time [eventName] arrives on [channelName], with the
/// event's data as JSON. Leave [eventName] empty for every event on the
/// channel. Keeps listening across pages until hibiraUnsubscribe; to listen
/// only while a page is open, use the HibiraEventListener widget instead.
/// Works before hibiraConnect too: events start once connected.
Future hibiraSubscribe(
  String channelName,
  String? eventName,
  Future Function(dynamic data) onEvent,
) async {
  HibiraFF.listen(channelName, eventName ?? '', onEvent);
}
