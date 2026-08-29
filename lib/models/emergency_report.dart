import 'package:flutter/material.dart';
import 'dart:math';

class EmergencyReport {
  final String reportId;
  final String reportLabel;
  final String userId;
  final String userName;
  final String emergencyType;
  String status;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;
  final String address;
  final String barangay;
  final Map<String, dynamic> details;
  String? dispatcherId;
  String? dispatcherName;
  DateTime? acknowledgedAt;
  DateTime? resolvedAt;

  EmergencyReport({
    required this.reportId,
    required this.reportLabel,
    required this.userId,
    required this.userName,
    required this.emergencyType,
    required this.status,
    required this.createdAt,
    this.latitude,
    this.longitude,
    required this.address,
    required this.barangay,
    required this.details,
    this.dispatcherId,
    this.dispatcherName,
    this.acknowledgedAt,
    this.resolvedAt,
  });

  factory EmergencyReport.fromMap(
    Map<dynamic, dynamic> map,
    String key, {
    String reportLabel = 'crime-report',
  }) {
    // ── Location ──────────────────────────────────────────────────────────────
    final location = map['Location'] as Map? ?? {};
    final rawLat = _parseDouble(location['Latitude']);
    final rawLng = _parseDouble(location['Longitude']);

    final lat = _isValidPanaboCoord(rawLat, rawLng) ? rawLat : null;
    final lng = _isValidPanaboCoord(rawLat, rawLng) ? rawLng : null;

    final rawAddress = location['Address']?.toString() ?? 'Unknown Location';

    // ── Details ───────────────────────────────────────────────────────────────
    final rawDetails = map['Details'] as Map? ?? {};
    final details = Map<String, dynamic>.from(rawDetails);

    // ── Emergency type ────────────────────────────────────────────────────────
    final rawType = (map['EmergencyType'] ?? details['type'] ?? 'other')
        .toString()
        .trim();
    final emergencyType = _capitalise(rawType);

    // ── Date ──────────────────────────────────────────────────────────────────
    final createdAt = _parseDate(
      map['Timestamp']?.toString(),
      map['CreatedAt']?.toString(),
    );

    // ── Barangay ──────────────────────────────────────────────────────────────
    final barangay = _extractBarangay(
      rawAddress,
      map['Barangay']?.toString(),
      lat,
      lng,
    );

    // ── Address ───────────────────────────────────────────────────────────────
    final address = _buildAddress(rawAddress, barangay, lat, lng);

    // ── Report ID ─────────────────────────────────────────────────────────────
    final reportId = (map['ReportId']?.toString().isNotEmpty == true)
        ? map['ReportId'].toString()
        : key;

    return EmergencyReport(
      reportId: reportId,
      reportLabel: (map['ReportLabel']?.toString().isNotEmpty == true)
          ? map['ReportLabel'].toString()
          : reportLabel,
      userId: map['UserId']?.toString() ?? '',
      userName: map['UserName']?.toString() ?? 'Unknown User',
      emergencyType: emergencyType,
      status: map['Status']?.toString() ?? 'Pending',
      createdAt: createdAt,
      latitude: lat,
      longitude: lng,
      address: address,
      barangay: barangay,
      details: details,
      dispatcherId: map['DispatcherId']?.toString(),
      dispatcherName: map['DispatcherName']?.toString(),
      acknowledgedAt: DateTime.tryParse(map['AcknowledgedAt']?.toString() ?? ''),
      resolvedAt: DateTime.tryParse(map['ResolvedAt']?.toString() ?? ''),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _capitalise(String s) {
    if (s.isEmpty) return 'Other';
    return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
  }

  static DateTime _parseDate(String? isoVal, String? formattedVal) {
    if (isoVal != null && isoVal.isNotEmpty) {
      final dt = DateTime.tryParse(isoVal);
      if (dt != null) return dt;
    }
    if (formattedVal != null && formattedVal.isNotEmpty) {
      final dt = _parseFormattedDate(formattedVal);
      if (dt != null) return dt;
    }
    return DateTime.now();
  }

  static DateTime? _parseFormattedDate(String val) {
    try {
      final spaceIdx = val.indexOf(' ');
      if (spaceIdx == -1) return null;
      final datePart = val.substring(0, spaceIdx);
      final timePart = val.substring(spaceIdx + 1);

      final dp = datePart.split('/');
      final tp = timePart.split(':');
      if (dp.length != 3 || tp.length != 3) return null;

      final month = int.tryParse(dp[0]);
      final day = int.tryParse(dp[1]);
      final year = int.tryParse(dp[2]);
      final hour = int.tryParse(tp[0]);
      final minute = int.tryParse(tp[1]);
      final second = int.tryParse(tp[2]);

      if ([month, day, year, hour, minute, second].any((v) => v == null)) {
        return null;
      }
      return DateTime(year!, month!, day!, hour!, minute!, second!);
    } catch (_) {
      return null;
    }
  }

  static bool _isValidPanaboCoord(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    return lat >= 7.27 && lat <= 7.36 && lng >= 125.65 && lng <= 125.72;
  }

  static const Map<String, List<double>> _barangayCoords = {
    'Buenavista': [7.3125, 125.6780],
    'Cacao': [7.2950, 125.6920],
    'Cagangohan': [7.3200, 125.6950],
    'Consolacion': [7.3050, 125.6830],
    'Dapco': [7.3300, 125.7000],
    'Datu Abdul Dadia': [7.2900, 125.6700],
    'Gredu': [7.3090, 125.6760],
    'J.P. Laurel': [7.3060, 125.6880],
    'Kasilak': [7.3170, 125.6820],
    'Katipunan': [7.3010, 125.6950],
    'Kauswagan': [7.2980, 125.6800],
    'Kiotoy': [7.3250, 125.7050],
    'Little Panay': [7.3080, 125.6700],
    'Lower Panaga': [7.3150, 125.6620],
    'Mabunao': [7.3000, 125.6680],
    'Maduao': [7.2880, 125.6760],
    'Malativas': [7.2960, 125.7000],
    'Manay': [7.3350, 125.6900],
    'Nanyo': [7.3020, 125.7050],
    'New Malaga': [7.3100, 125.7100],
    'New Malitbog': [7.2930, 125.6850],
    'New Pandan': [7.3220, 125.6730],
    'New Visayas': [7.3080, 125.6990],
    'Panabo': [7.3090, 125.6840],
    'Panacan': [7.2870, 125.6820],
    'Salvacion': [7.3180, 125.6890],
    'San Francisco': [7.3140, 125.6780],
    'San Nicolas': [7.3060, 125.6810],
    'Santo Niño': [7.3050, 125.6760],
    'Sindaton': [7.2940, 125.6930],
    'Southern Davao': [7.3000, 125.6750],
    'Tagpore': [7.3260, 125.6810],
    'Tibungol': [7.3090, 125.6710],
    'Upper Licanan': [7.3190, 125.6960],
    'Waterfall': [7.3110, 125.6850],
  };

  static double _haversineMetres(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRad(double degrees) => degrees * pi / 180.0;

  static String _nearestBarangay(double lat, double lng) {
    String nearest = 'Unknown Barangay';
    double minDist = double.infinity;
    for (final entry in _barangayCoords.entries) {
      final dist = _haversineMetres(lat, lng, entry.value[0], entry.value[1]);
      if (dist < minDist) {
        minDist = dist;
        nearest = entry.key;
      }
    }
    return nearest;
  }

  static String _extractBarangay(
    String address,
    String? barangayField,
    double? lat,
    double? lng,
  ) {
    if (barangayField != null &&
        barangayField.isNotEmpty &&
        barangayField != 'Unknown Barangay') {
      final normalised = _matchKnownBarangay(barangayField);
      if (normalised != null) return normalised;
      return barangayField;
    }
    if (!address.startsWith('Lat:') && address != 'Location unavailable') {
      final fromAddress = _matchKnownBarangayInAddress(address);
      if (fromAddress != null) return fromAddress;
    }
    if (lat != null && lng != null) {
      return _nearestBarangay(lat, lng);
    }
    return 'Unknown Barangay';
  }

  static String? _matchKnownBarangay(String candidate) {
    final c = candidate
        .toLowerCase()
        .replaceAll(RegExp(r'brgy\.?\s*'), '')
        .trim();
    for (final name in _barangayCoords.keys) {
      if (name.toLowerCase() == c) return name;
    }
    for (final name in _barangayCoords.keys) {
      final n = name.toLowerCase();
      if (c.contains(n) || n.contains(c)) return name;
    }
    return null;
  }

  static String? _matchKnownBarangayInAddress(String address) {
    final cleaned = address
        .replaceAll(RegExp(r',?\s*Davao del Norte', caseSensitive: false), '')
        .replaceAll(RegExp(r',?\s*Philippines', caseSensitive: false), '')
        .trim();
    final segments = cleaned
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    for (final segment in segments) {
      final match = _matchKnownBarangay(segment);
      if (match != null) return match;
    }
    return null;
  }

  static String _buildAddress(
    String rawAddress,
    String barangay,
    double? lat,
    double? lng,
  ) {
    if (!rawAddress.startsWith('Lat:') &&
        rawAddress != 'Location unavailable' &&
        rawAddress != 'Unknown Location' &&
        rawAddress.isNotEmpty) {
      return rawAddress;
    }
    if (barangay != 'Unknown Barangay') {
      if (lat != null && lng != null) {
        return 'Brgy. $barangay, Panabo City '
            '(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})';
      }
      return 'Brgy. $barangay, Panabo City, Davao del Norte';
    }
    if (lat != null && lng != null) {
      return 'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}';
    }
    return 'Location unavailable';
  }

  static double? _parseDouble(dynamic val) {
    if (val == null) return null;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString());
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'ReportId': reportId,
      'ReportLabel': reportLabel,
      'UserId': userId,
      'UserName': userName,
      'EmergencyType': emergencyType.toLowerCase(),
      'Status': status,
      'Timestamp': createdAt.toIso8601String(),
      'Location': {
        'Latitude': latitude,
        'Longitude': longitude,
        'Address': address,
      },
      'Barangay': barangay,
      'Details': details,
      if (dispatcherId != null) 'DispatcherId': dispatcherId,
      if (dispatcherName != null) 'DispatcherName': dispatcherName,
      if (acknowledgedAt != null)
        'AcknowledgedAt': acknowledgedAt!.toIso8601String(),
      if (resolvedAt != null) 'ResolvedAt': resolvedAt!.toIso8601String(),
    };
  }

  // ── Response-time metrics ─────────────────────────────────────────────────

  Duration? get timeToDispatch =>
      acknowledgedAt?.difference(createdAt);

  Duration? get timeToResolve => (acknowledgedAt != null && resolvedAt != null)
      ? resolvedAt!.difference(acknowledgedAt!)
      : null;

  static String formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  // ── Display helpers ───────────────────────────────────────────────────────

  Color get statusColor {
    switch (status) {
      case 'Pending':
        return const Color(0xFFFB8C00);
      case 'Acknowledged':
        return const Color(0xFF1976D2);
      case 'Resolved':
        return const Color(0xFF43A047);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  Color get typeColor {
    switch (emergencyType.toLowerCase()) {
      case 'fire':
        return const Color(0xFFE53935);
      case 'medical':
        return const Color(0xFF8E24AA);
      case 'crime':
        return const Color(0xFF1565C0);
      case 'flood':
        return const Color(0xFF00838F);
      case 'accident':
        return const Color(0xFFEF6C00);
      case 'bubble':
        return const Color(0xFFD81B60);
      default:
        return const Color(0xFF546E7A);
    }
  }

  String get typeIcon {
    switch (emergencyType.toLowerCase()) {
      case 'fire':
        return '🔥';
      case 'medical':
        return '🏥';
      case 'crime':
        return '🚨';
      case 'flood':
        return '🌊';
      case 'accident':
        return '🚗';
      case 'bubble':
        return '🆘';
      default:
        return '⚠️';
    }
  }

  // 'bubble' is internal plumbing (matches LifeGuard360's report-label
  // vocabulary) — dispatchers should see "SOS Alert", not "Bubble".
  String get displayType =>
      emergencyType.toLowerCase() == 'bubble' ? 'SOS Alert' : emergencyType;
}
