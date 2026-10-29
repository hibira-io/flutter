/// Pusher Channels protocol (v7) client for Hibira and other
/// Pusher-compatible servers, in pure Dart.
///
/// ```dart
/// final hibira = HibiraClient('your-app-key',
///     options: HibiraOptions(authEndpoint: Uri.parse('https://api.example.com/hibira/auth')));
/// await hibira.connect();
///
/// final room = hibira.subscribePresence('presence-room-42');
/// room.memberAdded.listen((m) => print('${m.id} joined'));
/// room.bind('client-move', (e) => print('${e.userId} moved ${e.data}'));
/// room.trigger('client-move', {'x': 3, 'y': 4});
/// ```
library;

export 'src/auth.dart'
    show HibiraAuth, HibiraAuthorizer, HibiraUserAuth, HibiraUserAuthenticator;
export 'src/client.dart'
    show
        HibiraChannel,
        HibiraClient,
        HibiraConnectionState,
        HibiraMember,
        HibiraPresenceChannel,
        HibiraUser;
export 'src/event.dart' show HibiraEvent, HibiraException;
export 'src/options.dart' show HibiraOptions;
export 'src/socket.dart' show HibiraSocket, HibiraSocketConnector;
