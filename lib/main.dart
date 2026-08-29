// lib/main.dart  (Dispatcher App)
//
// Changes vs original:
//   + Firebase.initializeApp() added
//   + FCM background message handler registered
//   + flutter_local_notifications shows alert for background / killed-app messages
//   + DispatcherPresence.initialize() started on auto-login (saved session)
//
// Everything else (SplashRouter, session check, LoginScreen) is unchanged.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/dispatcher_screen.dart';
import 'services/auth_service.dart';
import 'services/dispatcher_presence.dart';
import 'core/app_colors.dart';

// ── Local notification plugin (module-level so background handler can use it) ─
final FlutterLocalNotificationsPlugin _localNotif =
    FlutterLocalNotificationsPlugin();

const String _kChannelId = 'lifeguard_dispatcher_alerts';
const String _kChannelName = 'LifeGuard360 Dispatcher Alerts';

// ── FCM background handler (app KILLED or backgrounded by OS) ─────────────────
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await _localNotif.initialize(settings: initSettings); // ← fixed

  final title = message.notification?.title ??
      message.data['title'] ??
      '🚨 New Emergency Report';
  final body = message.notification?.body ??
      message.data['body'] ??
      'A new report has been submitted.';
  final reportId = message.data['reportId'];

  // Deterministic ID (derived from the report, not delivery time) so a
  // redelivered FCM message for the same report replaces the existing
  // tray entry instead of stacking a duplicate.
  final notifId = ((reportId != null && reportId.isNotEmpty)
              ? reportId
              : '$title|$body')
          .hashCode &
      0x7FFFFFFF;

  await _localNotif.show(
    id: notifId,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: 'Real-time emergency report alerts for dispatchers',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
        fullScreenIntent: true,
        color: const Color(0xFF0088CC),
        icon: '@mipmap/ic_launcher',
        visibility: NotificationVisibility.public,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

// ── MAIN ──────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    ),
  );
  await _localNotif.initialize(settings: initSettings); // ← fixed

  await _localNotif
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kChannelId,
          _kChannelName,
          description: 'Real-time emergency report alerts for dispatchers',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );

  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

  runApp(const DispatcherApp());
}

// ── APP ───────────────────────────────────────────────────────────────────────
class DispatcherApp extends StatelessWidget {
  const DispatcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LifeGuard360 Dispatcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF0F4F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A2035),
          elevation: 0,
        ),
      ),
      home: const _SplashRouter(),
    );
  }
}

// ── SPLASH ROUTER ─────────────────────────────────────────────────────────────
class _SplashRouter extends StatefulWidget {
  const _SplashRouter();

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = await AuthService.getSession();
    if (!mounted) return;

    if (session != null) {
      // ✅ Auto-login path — restart presence tracking so OnlineStatus /
      // LastSeen keep updating and the onDisconnect() hook is re-armed
      // on Firebase's server for this session.
      final userId = session['userId']?.toString() ?? '';
      if (userId.isNotEmpty) {
        await DispatcherPresence.initialize(userId, 'DispatcherAccounts');
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DispatcherScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF0F4F8),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Icon(Icons.local_police, color: Colors.white, size: 42),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'LifeGuard360',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A2035),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'POLICE CRIME DISPATCHER',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 1.8,
              ),
            ),
            SizedBox(height: 32),
            CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
          ],
        ),
      ),
    );
  }
}
