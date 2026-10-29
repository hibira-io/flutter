// Listens on a public channel and prints its events.
//
//   dart run example/main.dart <app key> [channel]
import 'dart:io';

import 'package:hibira/hibira.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run example/main.dart <app key> [channel]');
    exit(64);
  }
  final hibira = HibiraClient(args[0]);
  hibira.stateChanges.listen((s) => print('connection: ${s.name}'));
  await hibira.connect();
  print('socket id: ${hibira.socketId}');

  final channel = hibira.subscribe(args.length > 1 ? args[1] : 'my-channel');
  await channel.whenSubscribed;
  print('subscribed to ${channel.name}; publish an event from the portal');
  channel.events.listen((e) => print('${e.name}: ${e.data}'));

  await ProcessSignal.sigint.watch().first;
  await hibira.dispose();
}
