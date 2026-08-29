import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../models/emergency_report.dart';

/// Thrown by [DispatcherService.acknowledgeReport] when another dispatcher
/// already claimed the report between the UI loading it and this dispatcher
/// tapping Dispatch. [claimedByName] is the other dispatcher's name, if known.
class ReportAlreadyDispatchedException implements Exception {
  final String? claimedByName;
  ReportAlreadyDispatchedException(this.claimedByName);

  @override
  String toString() => claimedByName != null
      ? 'Report already dispatched by $claimedByName'
      : 'Report already dispatched by another unit';
}

/// Thrown by [DispatcherService.acknowledgeReport] when the dispatcher
/// already has a different report Acknowledged — a dispatcher may only
/// have one dispatched report in progress at a time, and must resolve it
/// before dispatching another.
class DispatcherHasActiveReportException implements Exception {
  @override
  String toString() =>
      'You already have a dispatched report in progress. Resolve it before '
      'dispatching another.';
}

class DispatcherService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  // ── FCM v1 send credentials ────────────────────────────────────────────
  // Same Firebase project/service account LifeGuard360 uses to push to
  // dispatchers — used here in reverse, to push an acknowledge message
  // back to the reporter's device.
  static const String _projectId = 'lifeguard-cefd9';
  static const String _clientEmail =
      'firebase-adminsdk-fbsvc@lifeguard-cefd9.iam.gserviceaccount.com';
  static const String _privateKey = '-----BEGIN PRIVATE KEY-----\n'
      'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDd9ORwnhrcoHi/\n'
      'JX7w3wtiM0//xX+FWDNPXyDbF3EEi4CmruszL1rfVpspbZvvdUOPEl3jrOlF/w5I\n'
      'gU1VAQL0ousQntbreouL3dwYBLZs57GjSwwOTAp7E0cTmzkl81G9VZvuQoLAcId4\n'
      'InaoK0XIDigELp8BilMWdwIJFgSbDpwoR7OrPbpgEZ1sO3G0JTSBIEadNiQydN0l\n'
      'WY5+PnjubyCCjI0eNJyv4OrAGm5Kr1iB7HPgOYHqU5bJHgpbaw3MN3PspXOEWML0\n'
      'ju4t6CQ754cBcs1HebxIkGSQSEzYowP4BAYp+GiFBOMLlLYKiLILtjUOqmfUaIhk\n'
      'QTkR91SRAgMBAAECggEAXhT1leT2pulgdUmMBsbMmPn+IYESPi/2Q+EjWKsVjWMi\n'
      'i8TeTop2nu+jgoqDDBvtIKKc6Kp9EN39rG8em/b7TT4XnKpvmE4QA5/tsMKinwQQ\n'
      '8JIZkJ/b23J+8MkdjsAWOEam+3X23WJ1kc8t87ev8w5JGQi3/pum/4E/fCF4n05m\n'
      'JOAdeI1VxmrfHnWSTMmGy6NBNWVpzDYRR9TGqqsha48l0wn+jotPM5D0AoYY2wqR\n'
      'BRwJ9v2Cn6mFB8Mm7+qVodUo5ngWjGAMWw/YCNoydBLY/qDl87HH1uHxiz6bCq9c\n'
      'jDrE2UPlweXo5wy4AeZBfuvzHJS6NxhgdPlysleD9wKBgQD81tKoKSgysyH5B++j\n'
      'Db5rvO4EoqkjOBHcVf7CKKCw1XTTW2wMcLMauxH/PY48cHEUnsk1JsEgTFZxorYT\n'
      '+cSc5T61iY4g5vMpavQAn4mRzjOYdfPMb+8UUURzvPZvZ4Op5CJwZkGUe6CWN3GX\n'
      'Mo5Ss0seiEIpmJ1UHVDCPYTFgwKBgQDguzvvCkaum797Y6iTmU2ph3iFrbA6XuCr\n'
      'X+qlfMBjrOAinzXUtCRpPwqvmJcHUULeI1mpVAujYad0JF9W7R7xB5r72SLg8o0Y\n'
      'Tv0Vz9okub7s2XgFmKTpGo+9Q27thlUpyIrJ7ZnDOZr6ImcXzCEQe5NfeC9Gc2Tq\n'
      'xYhUCMs1WwKBgA5rylQhFNPfd76Wf0qTjBrlCcZl6LPDjPE+TmuQmam8Yw9zFXSY\n'
      'MP8DUIF4Z1Z3K1v7uoo3jahj8kJE/5GgG2C/ipYcJGkoAxKHsScf8l7InhTCFYfB\n'
      'kqdcA0V+r6enBdF426YBjxgC/SPUQbxX+9ons88oAm4Q8FhN279Yduw1AoGBALiD\n'
      '4nysskYQ6NH1jGbLm0FTUnhnmGcEmXD8CtufJxNv0IN8tyUSV0b2lN6B6Zb/eGiN\n'
      'G8P0lq2ps2SfrIvhmuMJfI3FxWZun7xStmefRhubSpCLKYlmwBgIT/Z0lHJ/NhNd\n'
      'bd7Hr9TjykQP1Rdr6cXvwJvFQQOWIUjFsN5Wbgo7AoGBAMGPUHSOaKdSa8NBOxsw\n'
      '1tf25fV26VKn6XFwBgCUHgOdmHaZ69aiXHnPwyzo63+nx2eBIUU9Rt1WWDOpkkCk\n'
      'S0zGUSlzLL4VqaUEzfaJ+6mzT9yY+xR9r4rKsbe5ma8rrsNlGtBX7ZH8e0Vkj8uI\n'
      'FGHaYXE4NcQuK2ZouQP+RNt0\n'
      '-----END PRIVATE KEY-----';

  // This dispatcher displays Crime/Accident reports only. The SOS
  // floating-bubble alerts (`family-bubble-sos`) run through LifeGuard360's
  // own independent flow and are intentionally NOT watched here — Active
  // Reports must not fetch, display, or act on bubble reports.
  static const List<String> _watchedNodes = ['crime-report', 'accident-report'];

  // ── Stream: real-time via Firebase Realtime Database listeners ───────────
  //
  // Each watched node gets a live `.onValue` listener, so Pending/
  // Acknowledged/Resolved changes — made from this dispatcher or any other
  // connected client — are pushed to the UI immediately, with no polling
  // delay and no need to reopen the app. The merged stream is memoized so
  // repeated calls (e.g. from rebuilds) reuse the same subscriptions instead
  // of tearing down and reconnecting the listeners.
  Stream<List<EmergencyReport>>? _reportsStream;

  Stream<List<EmergencyReport>> watchReports() {
    return _reportsStream ??= _buildReportsStream();
  }

  Stream<List<EmergencyReport>> _buildReportsStream() {
    late final StreamController<List<EmergencyReport>> controller;
    final latestByNode = <String, List<EmergencyReport>>{};
    final subscriptions = <StreamSubscription>[];

    void emit() {
      final all = <EmergencyReport>[];
      for (final list in latestByNode.values) {
        all.addAll(list);
      }
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(all);
    }

    controller = StreamController<List<EmergencyReport>>.broadcast(
      onListen: () {
        for (final node in _watchedNodes) {
          subscriptions.add(
            FirebaseDatabase.instance.ref(node).onValue.listen((event) {
              latestByNode[node] = _parseSnapshot(event.snapshot, node);
              emit();
            }, onError: (e) => debugPrint('watchReports($node) error: $e')),
          );
        }
      },
      onCancel: () {
        for (final sub in subscriptions) {
          sub.cancel();
        }
        subscriptions.clear();
        _reportsStream = null;
      },
    );

    return controller.stream;
  }

  List<EmergencyReport> _parseSnapshot(DataSnapshot snapshot, String node) {
    final raw = snapshot.value;
    if (raw is! Map) return [];
    final reports = <EmergencyReport>[];
    raw.forEach((key, value) {
      if (value is Map) {
        reports.add(
          EmergencyReport.fromMap(
            Map<dynamic, dynamic>.from(value),
            key.toString(),
            reportLabel: node,
          ),
        );
      }
    });
    return reports;
  }

  // ── Acknowledge → sets "Acknowledged" ────────────────────────────────────
  // Status lifecycle: Pending → Acknowledged → Resolved
  //
  // Two atomic claims happen here, in order:
  //  1. The dispatcher's single active-report "slot" at
  //     /DispatcherActiveReport/{dispatcherId} — only succeeds if the
  //     dispatcher doesn't already have one, enforcing "one dispatched
  //     report per dispatcher at a time".
  //  2. The report itself — only succeeds while it's still Pending, so two
  //     dispatchers tapping Dispatch on the same report at nearly the same
  //     moment can't both win it.
  // If step 2 fails after step 1 succeeded, step 1's claim is rolled back —
  // the dispatcher didn't actually end up with a report, so their slot must
  // stay free.
  //
  // [dispatcherMessage] is optional — when provided it's saved on the report
  // and pushed straight to the reporter's device in LifeGuard360.
  Future<void> acknowledgeReport(
    String reportId, {
    String reportLabel = 'crime-report',
    required String dispatcherId,
    required String dispatcherName,
    String? dispatcherMessage,
  }) async {
    const newStatus = 'Acknowledged';
    final trimmedMessage = dispatcherMessage?.trim();
    final hasMessage = trimmedMessage != null && trimmedMessage.isNotEmpty;
    final now = DateTime.now().toIso8601String();

    final slotRef = FirebaseDatabase.instance.ref(
      'DispatcherActiveReport/$dispatcherId',
    );
    final slotResult = await slotRef.runTransaction((Object? data) {
      if (data != null) return Transaction.abort();
      return Transaction.success({
        'ReportId': reportId,
        'ReportLabel': reportLabel,
        'ClaimedAt': now,
      });
    });

    if (!slotResult.committed) {
      throw DispatcherHasActiveReportException();
    }

    String? claimedByName;
    final ref = FirebaseDatabase.instance.ref('$reportLabel/$reportId');
    final result = await ref.runTransaction((Object? data) {
      if (data == null || data is! Map) return Transaction.abort();
      final current = Map<String, dynamic>.from(data);
      final currentStatus = current['Status']?.toString() ?? 'Pending';
      if (currentStatus != 'Pending') {
        claimedByName = current['DispatcherName']?.toString();
        return Transaction.abort();
      }
      current['Status'] = newStatus;
      current['AcknowledgedAt'] = now;
      current['DispatcherId'] = dispatcherId;
      current['DispatcherName'] = dispatcherName;
      if (hasMessage) current['DispatcherMessage'] = trimmedMessage;
      return Transaction.success(current);
    });

    if (!result.committed) {
      await slotRef.remove(); // free the slot — this dispatcher got nothing
      throw ReportAlreadyDispatchedException(claimedByName);
    }

    debugPrint('✅ Acknowledged: /$reportLabel/$reportId → $newStatus (by $dispatcherName)');

    await _patchUserIndex(
      reportId: reportId,
      reportLabel: reportLabel,
      newStatus: newStatus,
      dispatcherMessage: hasMessage ? trimmedMessage : null,
    );
  }

  // ── Resolve ───────────────────────────────────────────────────────────────
  // Enforces the status lifecycle at the data layer (not just in the UI):
  // a report must already be Acknowledged (i.e. dispatched) before it can be
  // resolved. Reads the current status straight from the DB rather than
  // trusting the caller's possibly-stale copy, since multiple dispatchers
  // can be looking at the same report at once.
  Future<void> resolveReport(
    String reportId, {
    String reportLabel = 'crime-report',
  }) async {
    final report = await _fetchReport(reportId, reportLabel);
    final currentStatus = report?['Status']?.toString();
    if (currentStatus != 'Acknowledged') {
      throw StateError(
        'Report must be dispatched (Acknowledged) before it can be resolved '
        '(current status: ${currentStatus ?? 'unknown'}).',
      );
    }

    const newStatus = 'Resolved';

    await http
        .patch(
          Uri.parse('$_dbUrl$reportLabel/$reportId.json'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'Status': newStatus,
            'ResolvedAt': DateTime.now().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 10));

    debugPrint('✅ Resolved: /$reportLabel/$reportId → $newStatus');

    await _patchUserIndex(
      reportId: reportId,
      reportLabel: reportLabel,
      newStatus: newStatus,
    );

    // Free up the dispatcher's active-report slot so they can dispatch
    // another report.
    final dispatcherId = report?['DispatcherId']?.toString();
    if (dispatcherId != null && dispatcherId.isNotEmpty) {
      await _releaseDispatcherSlot(dispatcherId, reportId);
    }
  }

  // ── Read a report's full record straight from the DB ─────────────────────
  Future<Map<String, dynamic>?> _fetchReport(
    String reportId,
    String reportLabel,
  ) async {
    try {
      final resp = await http
          .get(Uri.parse('$_dbUrl$reportLabel/$reportId.json'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body);
      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('_fetchReport error: $e');
      return null;
    }
  }

  // ── Clear /DispatcherActiveReport/{dispatcherId} if it still points at
  // this report (only the report that's actually holding the slot may
  // release it) ─────────────────────────────────────────────────────────────
  Future<void> _releaseDispatcherSlot(
    String dispatcherId,
    String reportId,
  ) async {
    try {
      final ref = FirebaseDatabase.instance.ref(
        'DispatcherActiveReport/$dispatcherId',
      );
      final snap = await ref.get();
      final value = snap.value;
      if (value is Map && value['ReportId']?.toString() == reportId) {
        await ref.remove();
      }
    } catch (e) {
      debugPrint('_releaseDispatcherSlot error (non-fatal): $e');
    }
  }

  // ── Patch /UserEmergencyReports/{userId}/{reportId}/Status ───────────────
  Future<void> _patchUserIndex({
    required String reportId,
    required String reportLabel,
    required String newStatus,
    String? dispatcherMessage,
  }) async {
    try {
      final resp = await http
          .get(Uri.parse('$_dbUrl$reportLabel/$reportId.json'))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return;

      final data = json.decode(resp.body);
      if (data == null || data is! Map) return;

      final userId = data['UserId']?.toString() ?? '';
      if (userId.isEmpty) {
        debugPrint('⚠️ UserId missing on report — user index patch skipped');
        return;
      }

      final indexResp = await http
          .patch(
            Uri.parse('${_dbUrl}UserEmergencyReports/$userId/$reportId.json'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'Status': newStatus,
              if (dispatcherMessage != null)
                'DispatcherMessage': dispatcherMessage,
            }),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint(
        indexResp.statusCode < 300
            ? '✅ User index patched → "$newStatus" at /UserEmergencyReports/$userId/$reportId'
            : '⚠️ User index PATCH returned ${indexResp.statusCode}',
      );

      if (dispatcherMessage != null) {
        await _pushMessageToReporter(
          userId: userId,
          message: dispatcherMessage,
          reportId: reportId,
          reportLabel: reportLabel,
        );
      }
    } catch (e) {
      debugPrint('⚠️ _patchUserIndex error (non-fatal): $e');
    }
  }

  // ── Push the dispatcher's message straight to the reporter's device ──────
  Future<void> _pushMessageToReporter({
    required String userId,
    required String message,
    required String reportId,
    required String reportLabel,
  }) async {
    try {
      final tokenResp = await http
          .get(Uri.parse('${_dbUrl}Accounts/$userId/FcmToken.json'))
          .timeout(const Duration(seconds: 8));

      if (tokenResp.statusCode != 200) return;
      final token = tokenResp.body.trim().replaceAll('"', '');
      if (token.isEmpty || token == 'null') {
        debugPrint('⚠️ Reporter $userId has no FCM token — message not pushed');
        return;
      }

      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        debugPrint('❌ No access token — acknowledge message not pushed');
        return;
      }

      final resp = await http
          .post(
            Uri.parse(
                'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: json.encode({
              'message': {
                'token': token,
                'android': {'priority': 'high'},
                'apns': {
                  'headers': {
                    'apns-priority': '10',
                    'apns-push-type': 'background',
                  },
                  'payload': {
                    'aps': {'content-available': 1},
                  },
                },
                // Data-only, same as LifeGuard360's own sender — keeps the
                // app's local-notification call the single source of
                // display instead of a duplicate OS auto-post.
                'data': {
                  'title': '👮 Dispatcher acknowledged your report',
                  'body': message,
                  'type': 'dispatcher_message',
                  'reportId': reportId,
                  'reportLabel': reportLabel,
                  'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint(
        resp.statusCode == 200
            ? '✅ Acknowledge message pushed to reporter $userId'
            : '❌ Push to reporter failed ${resp.statusCode}: ${resp.body}',
      );
    } catch (e) {
      debugPrint('⚠️ _pushMessageToReporter error (non-fatal): $e');
    }
  }

  // ── OAuth2 access token via JWT (same pattern as LifeGuard360) ───────────
  Future<String?> _getAccessToken() async {
    try {
      final now = DateTime.now();
      final jwt = JWT({
        'iss': _clientEmail,
        'scope': 'https://www.googleapis.com/auth/firebase.messaging',
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': (now.millisecondsSinceEpoch ~/ 1000) + 3600,
      });

      final signed = jwt.sign(
        RSAPrivateKey(_privateKey),
        algorithm: JWTAlgorithm.RS256,
      );

      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': signed,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['access_token'] as String?;
      }
      debugPrint('❌ Token exchange failed: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('❌ _getAccessToken: $e');
      return null;
    }
  }

  // ── Group by barangay ─────────────────────────────────────────────────────
  Map<String, List<EmergencyReport>> groupByBarangay(
    List<EmergencyReport> reports, {
    bool includeResolved = false,
  }) {
    final filtered = includeResolved
        ? reports
        : reports.where((r) => r.status != 'Resolved').toList();

    final grouped = <String, List<EmergencyReport>>{};
    for (final r in filtered) {
      grouped.putIfAbsent(r.barangay, () => []).add(r);
    }
    return grouped;
  }
}
