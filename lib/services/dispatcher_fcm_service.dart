// lib/services/dispatcher_fcm_service.dart
//
// Handles FCM registration for the dispatcher app.
//
// On launch / login:
//   DispatcherFcmService.initialize(dispatcherId, dispatcherName)
//
// This saves the FCM token to:
//   /DispatcherTokens/{dispatcherId}/token   ← user app reads this to push alerts
//
// The token auto-refreshes and re-saves itself whenever Firebase rotates it.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DispatcherFcmService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  static const String _channelId = 'lifeguard_dispatcher_alerts';
  static const String _channelName = 'LifeGuard360 Dispatcher Alerts';

  static final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call once after the dispatcher logs in or resumes a saved session.
  /// Requests notification permission, grabs the FCM token, saves it to
  /// Firebase, and wires up foreground message handling.
  static Future<void> initialize({
    required String dispatcherId,
    required String dispatcherName,
  }) async {
    try {
      // 1. Request permission
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // 2. Get token
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        print('⚠️ DispatcherFCM: token is null');
        return;
      }

      // 3. Init local notifications (needed for foreground alerts)
      await _initLocalNotifications();

      // 4. Save token to Firebase RTDB
      await _saveToken(
        dispatcherId: dispatcherId,
        dispatcherName: dispatcherName,
        token: token,
      );

      // 5. Cache token locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dispatcher_fcm_token', token);

      // 6. Show notification when app is in foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ??
            message.data['title'] ??
            '🚨 New Emergency Report';
        final body = message.notification?.body ??
            message.data['body'] ??
            'A new report has been submitted.';
        print('📲 DispatcherFCM foreground: $title');
        _showLocalNotification(
          title: title,
          body: body,
          reportId: message.data['reportId'],
        );
      });

      // 7. Auto-refresh token
      messaging.onTokenRefresh.listen((newToken) async {
        await _saveToken(
          dispatcherId: dispatcherId,
          dispatcherName: dispatcherName,
          token: newToken,
        );
        final p = await SharedPreferences.getInstance();
        await p.setString('dispatcher_fcm_token', newToken);
        print('🔄 DispatcherFCM token refreshed');
      });

      print('✅ DispatcherFCM initialized for $dispatcherName ($dispatcherId)');
    } catch (e) {
      print('❌ DispatcherFcmService.initialize: $e');
    }
  }

  /// Remove this dispatcher's token from Firebase on logout so they stop
  /// receiving notifications after signing out.
  static Future<void> removeToken(String dispatcherId) async {
    try {
      await http
          .delete(Uri.parse('${_dbUrl}DispatcherTokens/$dispatcherId.json'))
          .timeout(const Duration(seconds: 10));
      print('🗑️ DispatcherFCM token removed for $dispatcherId');
    } catch (e) {
      print('⚠️ DispatcherFcmService.removeToken: $e');
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  static Future<void> _saveToken({
    required String dispatcherId,
    required String dispatcherName,
    required String token,
  }) async {
    await http
        .patch(
          Uri.parse('${_dbUrl}DispatcherTokens/$dispatcherId.json'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'token': token,
            'dispatcherName': dispatcherName,
            'updatedAt': DateTime.now().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 10));
    print('✅ DispatcherFCM token saved for $dispatcherId');
  }

  static Future<void> _initLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotif.initialize(settings: initSettings);

    // Create the high-priority Android notification channel
    await _localNotif
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Real-time emergency report alerts for dispatchers',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            showBadge: true,
          ),
        );
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? reportId,
  }) async {
    // Deterministic ID (derived from the report, not delivery time) so a
    // redelivered FCM message for the same report replaces the existing
    // tray entry instead of stacking a duplicate.
    final id = ((reportId != null && reportId.isNotEmpty)
                ? reportId
                : '$title|$body')
            .hashCode &
        0x7FFFFFFF;
    await _localNotif.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription:
              'Real-time emergency report alerts for dispatchers',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: true,
          color: Color(0xFF0088CC),
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
