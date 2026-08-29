import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// AuthService — stores dispatcher accounts in Firebase Realtime Database
/// at /DispatcherAccounts/{auto-id} using the same REST approach as the
/// LifeGuard360 main app (firebase_realtime_database.dart).
///
/// Session persistence: saves login info to SharedPreferences so the user
/// is automatically taken to the dashboard on next app launch.
class AuthService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  // SharedPreferences keys
  static const String _keyIsLoggedIn = 'dispatcher_is_logged_in';
  static const String _keyUserId = 'dispatcher_user_id';
  static const String _keyFullName = 'dispatcher_full_name';
  static const String _keyEmail = 'dispatcher_email';
  static const String _keyRank = 'dispatcher_rank';
  static const String _keyBadgeNumber = 'dispatcher_badge_number';

  // ── SESSION ──────────────────────────────────────────────────────────────────

  /// Save session data after a successful login.
  static Future<void> saveSession(Map<String, dynamic> loginResult) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUserId, loginResult['userId'] ?? '');
    await prefs.setString(_keyFullName, loginResult['fullName'] ?? '');
    await prefs.setString(_keyEmail, loginResult['email'] ?? '');
    await prefs.setString(_keyRank, loginResult['rank'] ?? '');
    await prefs.setString(_keyBadgeNumber, loginResult['badgeNumber'] ?? '');
  }

  /// Returns the saved session, or null if the user is not logged in.
  static Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
    if (!isLoggedIn) return null;

    return {
      'success': true,
      'userId': prefs.getString(_keyUserId) ?? '',
      'fullName': prefs.getString(_keyFullName) ?? 'Dispatcher',
      'email': prefs.getString(_keyEmail) ?? '',
      'rank': prefs.getString(_keyRank) ?? '',
      'badgeNumber': prefs.getString(_keyBadgeNumber) ?? '',
    };
  }

  /// Clears the session — call this on logout.
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyFullName);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyRank);
    await prefs.remove(_keyBadgeNumber);
  }

  // ── SIGN UP ─────────────────────────────────────────────────────────────────
  // Saves to /DispatcherAccounts/{auto-id} in Firebase
  static Future<Map<String, dynamic>> signUp({
    required String fullName,
    required String badgeNumber,
    required String rank,
    required String email,
    required String password,
  }) async {
    email = email.trim().toLowerCase();

    try {
      // 1. Check if email already exists
      final checkResp = await http
          .get(Uri.parse('${_dbUrl}DispatcherAccounts.json'))
          .timeout(const Duration(seconds: 20));

      if (checkResp.statusCode == 200) {
        final raw = json.decode(checkResp.body);
        if (raw != null && raw is Map) {
          final exists = raw.values.any(
            (a) =>
                a is Map &&
                (a['Email']?.toString().toLowerCase() ?? '') == email,
          );
          if (exists) {
            return {
              'success': false,
              'error': 'This email is already registered. Please log in.',
            };
          }
        }
      }

      // 2. POST to Firebase — creates /DispatcherAccounts/{auto-id}
      final now = DateTime.now().toIso8601String();
      final body = json.encode({
        'FullName': fullName.trim(),
        'BadgeNumber': badgeNumber.trim(),
        'Rank': rank,
        'Email': email,
        'Password': password,
        'Role': 'Dispatcher',
        'Status': 'Active',
        'CreatedAt': now,
      });

      final saveResp = await http
          .post(
            Uri.parse('${_dbUrl}DispatcherAccounts.json'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 20));

      if (saveResp.statusCode >= 200 && saveResp.statusCode < 300) {
        final data = json.decode(saveResp.body);
        return {'success': true, 'userId': data['name']};
      } else {
        return {
          'success': false,
          'error':
              'Failed to save account (HTTP ${saveResp.statusCode}).\n'
              'Go to Firebase Console → Realtime Database → Rules\n'
              'and set ".write": true temporarily to test.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error. Check your internet.\nDetails: $e',
      };
    }
  }

  // ── LOGIN ────────────────────────────────────────────────────────────────────
  // Reads /DispatcherAccounts, matches by email then checks password
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    email = email.trim().toLowerCase();

    try {
      final resp = await http
          .get(Uri.parse('${_dbUrl}DispatcherAccounts.json'))
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        return {
          'success': false,
          'error':
              'Server error (HTTP ${resp.statusCode}).\n'
              'Check Firebase Realtime Database rules.',
        };
      }

      final raw = json.decode(resp.body);

      if (raw == null || raw is! Map || raw.isEmpty) {
        return {
          'success': false,
          'error': 'No accounts found. Please create an account first.',
        };
      }

      // Find matching email
      String? matchedId;
      Map<String, dynamic>? matchedAcc;

      for (final entry in (raw as Map).entries) {
        final acc = entry.value;
        if (acc is Map &&
            (acc['Email']?.toString().toLowerCase() ?? '') == email) {
          matchedId = entry.key.toString();
          matchedAcc = Map<String, dynamic>.from(acc);
          break;
        }
      }

      if (matchedAcc == null) {
        return {
          'success': false,
          'error': 'Email not found. Please check your email or sign up.',
        };
      }

      // Check password
      if (matchedAcc['Password']?.toString() != password) {
        return {
          'success': false,
          'error': 'Incorrect password. Please try again.',
        };
      }

      return {
        'success': true,
        'userId': matchedId,
        'fullName': matchedAcc['FullName'] ?? 'Dispatcher',
        'email': matchedAcc['Email'] ?? '',
        'rank': matchedAcc['Rank'] ?? '',
        'badgeNumber': matchedAcc['BadgeNumber'] ?? '',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error. Check your internet.\nDetails: $e',
      };
    }
  }

  // ── UPDATE PROFILE ──────────────────────────────────────────────────────────
  // Patches /DispatcherAccounts/{userId} with edited profile fields.
  // Pass a non-empty [newPassword] to also change the account password;
  // omit or leave empty to keep the current password unchanged.
  static Future<Map<String, dynamic>> updateProfile({
    required String userId,
    required String fullName,
    required String badgeNumber,
    required String rank,
    required String email,
    String? newPassword,
  }) async {
    email = email.trim().toLowerCase();

    if (userId.isEmpty) {
      return {
        'success': false,
        'error': 'Missing user session. Please log in again.',
      };
    }

    try {
      // If the email changed, make sure it isn't already used by another account.
      final checkResp = await http
          .get(Uri.parse('${_dbUrl}DispatcherAccounts.json'))
          .timeout(const Duration(seconds: 20));

      if (checkResp.statusCode == 200) {
        final raw = json.decode(checkResp.body);
        if (raw != null && raw is Map) {
          final takenByOther = (raw as Map).entries.any(
            (e) =>
                e.key.toString() != userId &&
                e.value is Map &&
                (e.value['Email']?.toString().toLowerCase() ?? '') == email,
          );
          if (takenByOther) {
            return {
              'success': false,
              'error': 'This email is already used by another account.',
            };
          }
        }
      }

      final body = <String, dynamic>{
        'FullName': fullName.trim(),
        'BadgeNumber': badgeNumber.trim(),
        'Rank': rank.trim(),
        'Email': email,
      };
      if (newPassword != null && newPassword.isNotEmpty) {
        body['Password'] = newPassword;
      }

      final resp = await http
          .patch(
            Uri.parse('${_dbUrl}DispatcherAccounts/$userId.json'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return {
          'success': true,
          'userId': userId,
          'fullName': fullName.trim(),
          'email': email,
          'rank': rank.trim(),
          'badgeNumber': badgeNumber.trim(),
        };
      }
      return {
        'success': false,
        'error': 'Failed to update profile (HTTP ${resp.statusCode}).',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error. Check your internet.\nDetails: $e',
      };
    }
  }
}
