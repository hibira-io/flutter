import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hibira/hibira.dart';
import 'package:hibira_push/hibira_push.dart';

// Pass your own values with --dart-define, for example
//   flutter run --dart-define=HIBIRA_APP_KEY=abc --dart-define=HIBIRA_AUTH_ENDPOINT=https://api.example.com/hibira/auth
// The app key is public; never put the app secret in an app.
const appKey = String.fromEnvironment('HIBIRA_APP_KEY');
const host = String.fromEnvironment(
  'HIBIRA_HOST',
  defaultValue: 'ws.hibira.io',
);
const port = int.fromEnvironment('HIBIRA_PORT', defaultValue: 443);
const useTLS = bool.fromEnvironment('HIBIRA_TLS', defaultValue: true);
const authEndpoint = String.fromEnvironment('HIBIRA_AUTH_ENDPOINT');
const pushInstanceId = String.fromEnvironment('HIBIRA_PUSH_INSTANCE_ID');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hibira example',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5),
        brightness: Brightness.dark,
      ),
      home: const DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: TabBar(
            tabs: [
              Tab(icon: Icon(Icons.bolt), text: 'Channels'),
              Tab(icon: Icon(Icons.notifications), text: 'Push'),
            ],
          ),
          body: SafeArea(
            child: TabBarView(children: [ChannelsTab(), PushTab()]),
          ),
        ),
      ),
    );
  }
}

class ChannelsTab extends StatefulWidget {
  const ChannelsTab({super.key});

  @override
  State<ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends State<ChannelsTab> {
  HibiraClient? _client;
  HibiraChannel? _channel;
  final _subs = <StreamSubscription<Object?>>[];
  final _channelName = TextEditingController(text: 'my-channel');
  final _log = <String>[];

  @override
  void initState() {
    super.initState();
    if (appKey.isEmpty) return;
    final client = HibiraClient(
      appKey,
      options: HibiraOptions(
        host: host,
        port: port,
        useTLS: useTLS,
        authEndpoint: authEndpoint.isEmpty ? null : Uri.parse(authEndpoint),
      ),
    );
    _client = client;
    _subs
      ..add(client.stateChanges.listen((_) => setState(() {})))
      ..add(client.errors.listen((e) => _add('error: ${e.message}')))
      ..add(
        client.events.listen((e) => _add('${e.channel} ${e.name} ${e.data}')),
      );
    client.connect().catchError((Object e) => _add('connect failed: $e'));
  }

  void _add(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, line));
  }

  void _subscribe() {
    final client = _client;
    final name = _channelName.text.trim();
    if (client == null || name.isEmpty) return;
    _channel?.unsubscribe();
    final channel = client.subscribe(name);
    _subs.add(channel.errors.listen((e) => _add('$name: ${e.message}')));
    if (channel is HibiraPresenceChannel) {
      _subs
        ..add(channel.memberAdded.listen((_) => setState(() {})))
        ..add(channel.memberRemoved.listen((_) => setState(() {})));
    }
    channel.whenSubscribed.then((_) => setState(() {}), onError: (_) {});
    setState(() => _channel = channel);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _client?.dispose();
    _channelName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    if (client == null) {
      return const _Hint(
        'Run with --dart-define=HIBIRA_APP_KEY=<your app key> '
        '(from the Hibira portal).',
      );
    }
    final channel = _channel;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${client.state.name}${client.socketId == null ? '' : ' · ${client.socketId}'}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _channelName,
                  decoration: const InputDecoration(
                    labelText: 'Channel',
                    helperText:
                        'private- and presence- need HIBIRA_AUTH_ENDPOINT',
                  ),
                  onSubmitted: (_) => _subscribe(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _subscribe,
                child: const Text('Subscribe'),
              ),
            ],
          ),
          if (channel != null) ...[
            const SizedBox(height: 12),
            Text(
              '${channel.name}: ${channel.isSubscribed ? 'subscribed' : 'subscribing…'}',
            ),
            if (channel is HibiraPresenceChannel)
              Wrap(
                spacing: 6,
                children: [
                  for (final m in channel.members.values)
                    Chip(
                      label: Text(
                        m.id == channel.myId ? '${m.id} (you)' : m.id,
                      ),
                    ),
                ],
              ),
          ],
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_log[i], style: theme.textTheme.bodySmall),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PushTab extends StatefulWidget {
  const PushTab({super.key});

  @override
  State<PushTab> createState() => _PushTabState();
}

class _PushTabState extends State<PushTab> {
  final _push = HibiraPush.instance;
  final _subs = <StreamSubscription<Object?>>[];
  final _interest = TextEditingController(text: 'hello');
  final _log = <String>[];
  Set<String> _interests = {};
  bool? _allowed;
  String? _error;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (!_supported || pushInstanceId.isEmpty) return;
    _start();
  }

  Future<void> _start() async {
    try {
      await _push.start(pushInstanceId);
      _subs
        ..add(
          _push.onMessage.listen(
            (m) => _add('message: ${m.title} ${m.body} ${m.data}'),
          ),
        )
        ..add(_push.onMessageOpenedApp.listen((m) => _add('opened: ${m.data}')))
        ..add(
          _push.onInterestsChanged.listen(
            (i) => setState(() => _interests = i),
          ),
        );
      final initial = await _push.getInitialMessage();
      if (initial != null) _add('launched by: ${initial.data}');
      final allowed = await _push.requestPermission();
      final interests = await _push.getDeviceInterests();
      setState(() {
        _allowed = allowed;
        _interests = interests;
      });
    } on HibiraPushException catch (e) {
      setState(() => _error = e.message);
    }
  }

  void _add(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, line));
  }

  Future<void> _addInterest() async {
    final name = _interest.text.trim();
    if (name.isEmpty) return;
    try {
      await _push.addDeviceInterest(name);
      final interests = await _push.getDeviceInterests();
      setState(() => _interests = interests);
    } on HibiraPushException catch (e) {
      _add('error: ${e.message}');
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _interest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const _Hint('Push runs on Android and iOS.');
    if (pushInstanceId.isEmpty) {
      return const _Hint(
        'Run with --dart-define=HIBIRA_PUSH_INSTANCE_ID=<instance id> '
        '(on the app page in the Hibira portal, Push notifications).',
      );
    }
    if (_error != null) return _Hint(_error!);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _allowed == null
                ? 'Starting…'
                : _allowed!
                ? 'Notifications allowed'
                : 'Notifications not allowed',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _interest,
                  decoration: const InputDecoration(labelText: 'Interest'),
                  onSubmitted: (_) => _addInterest(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _addInterest, child: const Text('Add')),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (final i in _interests)
                InputChip(
                  label: Text(i),
                  onDeleted: () async {
                    await _push.removeDeviceInterest(i);
                    final interests = await _push.getDeviceInterests();
                    setState(() => _interests = interests);
                  },
                ),
            ],
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView(
              children: [
                for (final line in _log)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(line, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
