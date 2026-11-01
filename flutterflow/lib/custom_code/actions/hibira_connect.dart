// Automatic FlutterFlow imports
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/actions/index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'dart:async';

import 'package:hibira/hibira.dart';

/// Connects the app to Hibira. Call it once, for example in the first page's
/// On Page Load. Calling it again with the same settings does nothing; new
/// settings replace the old connection.
///
/// [authEndpoint] signs private and presence channels (your backend, the
/// same URL pusher-js would use). [authToken] is sent to it as
/// `Authorization: Bearer <token>`. Returns true once connected.
Future<bool> hibiraConnect(
  String appKey,
  String? host,
  String? authEndpoint,
  String? authToken,
) async {
  try {
    await HibiraFF.connect(
      appKey: appKey,
      host: host,
      authEndpoint: authEndpoint,
      authToken: authToken,
    );
    return true;
  } catch (e) {
    debugPrint('Hibira: connect failed: $e');
    return false;
  }
}

/// The one Hibira connection shared by the Hibira actions and widgets.
class HibiraFF {
  HibiraFF._();

  static String? _settings;
  static final Map<String, int> _users = {};
  static final Map<String, _Listener> _listeners = {};
  static StreamSubscription<HibiraConnectionState>? _stateSub;

  /// The current client: null before the first [connect], replaced when
  /// [connect] gets new settings. Widgets listen to it to bind again.
  static final ValueNotifier<HibiraClient?> current = ValueNotifier(null);

  static final ValueNotifier<HibiraConnectionState> state = ValueNotifier(
    HibiraConnectionState.disconnected,
  );

  static HibiraClient? get client => current.value;

  static Future<void> connect({
    required String appKey,
    String? host,
    String? authEndpoint,
    String? authToken,
  }) async {
    final cleanHost = (host == null || host.trim().isEmpty)
        ? 'ws.hibira.io'
        : host.trim();
    final cleanAuth = (authEndpoint == null || authEndpoint.trim().isEmpty)
        ? null
        : authEndpoint.trim();
    final cleanToken = (authToken == null || authToken.isEmpty)
        ? null
        : authToken;
    final settings = [appKey, cleanHost, cleanAuth, cleanToken].join('\n');
    final old = current.value;
    if (old != null && _settings == settings) return old.connect();

    await _stateSub?.cancel();
    for (final l in _listeners.values) {
      await l.sub?.cancel();
    }
    final client = HibiraClient(
      appKey,
      options: HibiraOptions(
        host: cleanHost,
        authEndpoint: cleanAuth == null ? null : Uri.parse(cleanAuth),
        authHeaders: cleanToken == null
            ? const {}
            : {'Authorization': 'Bearer $cleanToken'},
      ),
    );
    _settings = settings;
    _stateSub = client.stateChanges.listen((s) => state.value = s);
    for (final name in _users.keys) {
      client.subscribe(name);
    }
    for (final l in _listeners.values) {
      l.bind(client);
    }
    current.value = client;
    await old?.dispose();
    await client.connect();
  }

  static Future<void> disconnect() async {
    await current.value?.disconnect();
  }

  /// Subscribes to [channelName] for one user (a widget or a listener). The
  /// channel is left when its last user calls [release]. Works before
  /// [connect] too: the subscription starts once connected.
  static HibiraChannel? hold(String channelName) {
    _users[channelName] = (_users[channelName] ?? 0) + 1;
    return current.value?.subscribe(channelName);
  }

  static void release(String channelName) {
    final left = (_users[channelName] ?? 1) - 1;
    if (left > 0) {
      _users[channelName] = left;
      return;
    }
    _users.remove(channelName);
    current.value?.unsubscribe(channelName);
  }

  /// Events named [eventName] on [channelName]; every app event when
  /// [eventName] is empty (`pusher:` internals left out).
  static Stream<HibiraEvent> eventsOf(HibiraChannel channel, String eventName) {
    return eventName.isEmpty
        ? channel.events.where((e) => !e.name.startsWith('pusher:'))
        : channel.on(eventName);
  }

  /// Runs [onEvent] for [eventName] on [channelName] until [stopListening].
  static void listen(
    String channelName,
    String eventName,
    Future Function(dynamic data) onEvent,
  ) {
    final key = '$channelName\n$eventName';
    if (_listeners.containsKey(key)) return;
    hold(channelName);
    final listener = _Listener(channelName, eventName, onEvent);
    _listeners[key] = listener;
    final client = current.value;
    if (client != null) listener.bind(client);
  }

  static void stopListening(String channelName) {
    final keys = _listeners.keys
        .where((k) => k.startsWith('$channelName\n'))
        .toList();
    for (final key in keys) {
      _listeners.remove(key)?.sub?.cancel();
      release(channelName);
    }
  }

  /// Presence members as JSON: `[{"id": "...", "info": {...}}]`.
  static List<dynamic> members(String channelName) {
    final channel = current.value?.channel(channelName);
    if (channel is! HibiraPresenceChannel) return [];
    return channel.members.values
        .map((m) => <String, dynamic>{'id': m.id, 'info': m.info})
        .toList();
  }
}

class _Listener {
  _Listener(this.channelName, this.eventName, this.onEvent);

  final String channelName;
  final String eventName;
  final Future Function(dynamic data) onEvent;
  StreamSubscription<HibiraEvent>? sub;

  void bind(HibiraClient client) {
    sub = HibiraFF.eventsOf(
      client.subscribe(channelName),
      eventName,
    ).listen((e) => onEvent(e.data));
  }
}
