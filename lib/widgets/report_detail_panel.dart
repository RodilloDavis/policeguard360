import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/emergency_report.dart';
import '../core/app_colors.dart';

class ReportDetailPanel extends StatelessWidget {
  final EmergencyReport? report;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onResolve;

  const ReportDetailPanel({
    super.key,
    this.report,
    this.onAcknowledge,
    this.onResolve,
  });

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

  ({double lat, double lng, bool isExact})? _resolveDestination() {
    if (report == null) return null;

    if (report!.latitude != null && report!.longitude != null) {
      return (lat: report!.latitude!, lng: report!.longitude!, isExact: true);
    }

    final coords = _barangayCoords[report!.barangay];
    if (coords != null) {
      return (lat: coords[0], lng: coords[1], isExact: false);
    }

    return null;
  }

  Future<void> _openNavigation(BuildContext context) async {
    final dest = _resolveDestination();
    if (dest == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No GPS coordinates available for this report.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final lat = dest.lat;
    final lng = dest.lng;

    if (!dest.isExact && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No exact GPS — navigating to Brgy. ${report!.barangay} center.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    final nativeUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );

    try {
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(nativeUri);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open maps: $e',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (report == null) {
      return Container(
        color: const Color(0xFFF8F9FA),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_outlined, size: 48, color: AppColors.grey),
              SizedBox(height: 16),
              Text(
                'Select a report to view details',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Tap on any report from the left panel',
                style: TextStyle(fontSize: 12, color: AppColors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final dest = _resolveDestination();
    final hasLocation = dest != null;

    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: report!.typeColor,
                gradient: LinearGradient(
                  colors: [
                    report!.typeColor,
                    report!.typeColor.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        report!.typeIcon,
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report!.emergencyType.toLowerCase() == 'bubble'
                                  ? 'SOS Alert — Needs Help Now'
                                  : '${report!.emergencyType} Emergency',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              report!.reportId.length > 20
                                  ? '...${report!.reportId.substring(report!.reportId.length - 15)}'
                                  : report!.reportId,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusBadge(
                        status: report!.status,
                        color: report!.statusColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_city,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Brgy. ${report!.barangay}, Panabo City',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable body ───────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Reporter ──────────────────────────────────────────────
                    _SectionHeader(title: 'REPORTER', icon: Icons.person),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.badge_outlined,
                      label: 'Name',
                      value: report!.userName,
                    ),
                    _InfoRow(
                      icon: Icons.fingerprint,
                      label: 'User ID',
                      value: report!.userId,
                    ),

                    const SizedBox(height: 16),

                    // ── Location ──────────────────────────────────────────────
                    _SectionHeader(
                      title: 'LOCATION',
                      icon: Icons.location_on_outlined,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.location_city,
                      label: 'Barangay',
                      value: 'Brgy. ${report!.barangay}',
                    ),
                    _InfoRow(
                      icon: Icons.business,
                      label: 'City',
                      value: 'Panabo City, Davao del Norte',
                    ),
                    _InfoRow(
                      icon: Icons.place_outlined,
                      label: 'Address',
                      value: report!.address,
                    ),
                    if (report!.latitude != null)
                      _InfoRow(
                        icon: Icons.gps_fixed,
                        label: 'GPS',
                        value:
                            '${report!.latitude!.toStringAsFixed(5)}, ${report!.longitude!.toStringAsFixed(5)}',
                      )
                    else
                      _InfoRow(
                        icon: Icons.gps_not_fixed,
                        label: 'GPS',
                        value: 'Using barangay location (no GPS)',
                      ),

                    if (dest != null) ...[
                      const SizedBox(height: 10),
                      _LocationPreviewMap(
                        latitude: dest.lat,
                        longitude: dest.lng,
                        label: 'Brgy. ${report!.barangay}, Panabo City',
                      ),
                    ],

                    const SizedBox(height: 12),

                    // ── Navigate Button ───────────────────────────────────────
                    _NavigateButton(
                      hasLocation: hasLocation,
                      isExactGps: dest?.isExact ?? false,
                      onTap: () => _openNavigation(context),
                    ),

                    const SizedBox(height: 16),

                    // ── Timestamp ─────────────────────────────────────────────
                    _SectionHeader(title: 'TIMESTAMP', icon: Icons.schedule),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.calendar_today,
                      label: 'Reported',
                      value: DateFormat(
                        'MMM dd, yyyy • hh:mm:ss a',
                      ).format(report!.createdAt),
                    ),
                    if (report!.dispatcherName != null)
                      _InfoRow(
                        icon: Icons.local_shipping_outlined,
                        label: 'Dispatched by',
                        value: report!.dispatcherName!,
                      ),
                    if (report!.timeToDispatch != null)
                      _InfoRow(
                        icon: Icons.timer_outlined,
                        label: 'Time to dispatch',
                        value: EmergencyReport.formatDuration(
                          report!.timeToDispatch!,
                        ),
                      ),
                    if (report!.timeToResolve != null)
                      _InfoRow(
                        icon: Icons.timer_outlined,
                        label: 'Time to resolve',
                        value: EmergencyReport.formatDuration(
                          report!.timeToResolve!,
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ── Additional details ────────────────────────────────────
                    if (report!.details.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'REPORT DETAILS',
                        icon: Icons.description_outlined,
                      ),
                      const SizedBox(height: 8),
                      ...report!.details.entries
                          .where(
                            (e) =>
                                e.value != null &&
                                e.value.toString().isNotEmpty &&
                                e.key != 'type',
                          )
                          .map(
                            (e) => _InfoRow(
                              icon: Icons.info_outline,
                              label: _formatKey(e.key),
                              value: e.value.toString(),
                            ),
                          ),
                      const SizedBox(height: 16),
                    ],

                    // ── Dispatch actions ──────────────────────────────────────
                    if (report!.status != 'Resolved') ...[
                      _SectionHeader(
                        title: 'DISPATCH ACTIONS',
                        icon: Icons.security_outlined,
                      ),
                      const SizedBox(height: 12),
                      if (report!.status == 'Pending') ...[
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: onAcknowledge,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.acknowledged,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Acknowledge Report',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Dispatch this report first — Resolve unlocks once '
                          'it\'s Acknowledged.',
                          style: TextStyle(fontSize: 11, color: AppColors.grey),
                        ),
                      ] else if (report!.status == 'Acknowledged') ...[
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: onResolve,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.resolved,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(
                              Icons.task_alt,
                              size: 18,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Mark as Resolved',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.resolved.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.resolved.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: AppColors.resolved,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'This report has been resolved',
                              style: TextStyle(
                                color: AppColors.resolved,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatKey(String key) {
    return key
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
        .join(' ');
  }
}

// ── Navigate Button Widget ────────────────────────────────────────────────────

class _NavigateButton extends StatelessWidget {
  final bool hasLocation;
  final bool isExactGps;
  final VoidCallback onTap;

  const _NavigateButton({
    required this.hasLocation,
    required this.isExactGps,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: hasLocation ? onTap : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              disabledBackgroundColor: AppColors.grey.withValues(alpha: 0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            icon: const Icon(
              Icons.navigation_rounded,
              size: 20,
              color: Colors.white,
            ),
            label: Text(
              hasLocation ? 'Navigate to Scene' : 'No Location Available',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: hasLocation ? Colors.white : AppColors.grey,
              ),
            ),
          ),
        ),
        if (hasLocation) ...[
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isExactGps ? Icons.gps_fixed : Icons.gps_not_fixed,
                size: 11,
                color: isExactGps ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 4),
              Text(
                isExactGps
                    ? 'Using exact GPS coordinates'
                    : 'Using barangay center (no exact GPS)',
                style: TextStyle(
                  fontSize: 10,
                  color: isExactGps ? AppColors.success : AppColors.warning,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: const Color(0xFFE8EDF5))),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.grey),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.darkGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusBadge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// Small static map preview shown under the GPS row so a dispatcher can see
// at a glance where a report is from, without leaving the detail panel.
// liteModeEnabled renders it as a static bitmap — the right choice inside a
// SingleChildScrollView, since it avoids the map's own drag/zoom gestures
// fighting the page scroll. Tapping it opens a full-screen, fully
// interactive map centered on the same spot.
//
// Complements _NavigateButton/_openNavigation above (which hands off to an
// external turn-by-turn nav app) rather than replacing it — this is for a
// quick in-app glance, that's for actually driving there.
class _LocationPreviewMap extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String label;

  const _LocationPreviewMap({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final position = LatLng(latitude, longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            // liteMode's own native view has a built-in tap handler (it
            // tries to hand the tap off to the Google Maps app) that
            // otherwise wins the touch before Flutter's GestureDetector
            // ever sees it — AbsorbPointer blocks that so our tap layer on
            // top gets it instead.
            AbsorbPointer(
              child: GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: position, zoom: 16),
                liteModeEnabled: true,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                scrollGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                zoomGesturesEnabled: false,
                markers: {
                  Marker(
                    markerId: const MarkerId('report_location'),
                    position: position,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed,
                    ),
                  ),
                },
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          _FullLocationMap(position: position, label: label),
                    ),
                  ),
                ),
              ),
            ),
            // Affordance so a static-looking preview still reads as
            // tappable — liteMode has no built-in hint that it opens up.
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.fullscreen,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Full-screen, pannable/zoomable map opened by tapping the preview above.
class _FullLocationMap extends StatelessWidget {
  final LatLng position;
  final String label;

  const _FullLocationMap({required this.position, required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: position, zoom: 17),
        myLocationButtonEnabled: false,
        markers: {
          Marker(
            markerId: const MarkerId('report_location'),
            position: position,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
          ),
        },
      ),
    );
  }
}
