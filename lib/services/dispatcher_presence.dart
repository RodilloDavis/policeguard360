import 'package:firebase_database/firebase_database.dart';

class DispatcherPresence {
  static Future<void> initialize(String uid, String node) async {
    final db = FirebaseDatabase.instance;
    final ref = db.ref('$node/$uid');

    // Listen to connection state
    db.ref('.info/connected').onValue.listen((event) {
      final connected = event.snapshot.value as bool? ?? false;

      if (connected) {
        // When connection drops — auto-write Offline (runs on Firebase server)
        ref.onDisconnect().update({
          'OnlineStatus': 'Offline',
          'LastSeen': ServerValue.timestamp,
        });

        // Write Online immediately
        ref.update({
          'OnlineStatus': 'Online',
          'LastSeen': ServerValue.timestamp,
        });
      }
    });
  }
}
