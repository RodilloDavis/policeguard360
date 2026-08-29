import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_colors.dart';
import '../models/emergency_report.dart';
import '../services/dispatcher_service.dart';
import '../services/dispatcher_fcm_service.dart';
import '../services/auth_service.dart';
import '../widgets/barangay_group.dart';
import '../widgets/map_panel.dart';
import '../widgets/report_detail_panel.dart';
import 'login_screen.dart';
import 'profile_settings_screen.dart';

const double _kPanelWidth = 300.0;
const Duration _kPanelDuration = Duration(milliseconds: 320);
const Curve _kPanelCurve = Curves.easeInOutCubic;

class DispatcherScreen extends StatefulWidget {
  const DispatcherScreen({super.key});

  @override
  State<DispatcherScreen> createState() => _DispatcherScreenState();
}

class _DispatcherScreenState extends State<DispatcherScreen>
    with TickerProviderStateMixin {
  final DispatcherService _service = DispatcherService();
  late final Stream<List<EmergencyReport>> _reportsStream =
      _service.watchReports();

  EmergencyReport? _selectedReport;
  String _statusFilter = 'All';
  bool _leftOpen = false;
  bool _rightOpen = false;

  // ── New-report alert (sound + vibration) + latest-reports cache ───────────
  StreamSubscription<List<EmergencyReport>>? _alertSub;
  Set<String>? _knownPendingIds;
  List<EmergencyReport> _latestReports = [];

  late final AnimationController _leftCtrl;
  late final AnimationController _rightCtrl;
  late final Animation<double> _leftAnim;
  late final Animation<double> _rightAnim;

  final _filters = ['All', 'Pending', 'Acknowledged', 'Resolved'];

  @override
  void initState() {
    super.initState();
    // Opens straight to the map — the reports panel starts collapsed so
    // the dispatcher sees the full map immediately instead of it being
    // partly covered by the list.
    _leftCtrl = AnimationController(vsync: this, duration: _kPanelDuration)
      ..value = 0.0;
    _rightCtrl = AnimationController(vsync: this, duration: _kPanelDuration)
      ..value = 0.0;
    _leftAnim = CurvedAnimation(parent: _leftCtrl, curve: _kPanelCurve);
    _rightAnim = CurvedAnimation(parent: _rightCtrl, curve: _kPanelCurve);

    // Register FCM token so the user app can push new-report alerts here.
    _registerFcmToken();

    // Independent of the UI's StreamBuilder — fires a sound + vibration the
    // moment a new Pending report shows up, whether or not this screen is
    // currently rebuilding for other reasons. Also keeps a cheap local cache
    // of the latest reports so _acknowledge() can pre-check the "one active
    // dispatch per dispatcher" rule without waiting on a network round trip.
    _alertSub = _reportsStream.listen(_onReportsStreamUpdate);
  }

  void _onReportsStreamUpdate(List<EmergencyReport> reports) {
    _latestReports = reports;
    _checkForNewPendingReports(reports);
  }

  // The first snapshot just establishes the baseline (the reports that were
  // already Pending when the dispatcher opened the app) — only report IDs
  // that appear in a *later* snapshot trigger the alert.
  void _checkForNewPendingReports(List<EmergencyReport> reports) {
    final pendingIds = reports
        .where((r) => r.status == 'Pending')
        .map((r) => r.reportId)
        .toSet();
    final previous = _knownPendingIds;
    _knownPendingIds = pendingIds;
    if (previous == null) return;
    if (pendingIds.difference(previous).isNotEmpty) {
      HapticFeedback.vibrate();
      SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _registerFcmToken() async {
    final session = await AuthService.getSession();
    if (session == null) return;
    await DispatcherFcmService.initialize(
      dispatcherId: session['userId'] ?? '',
      dispatcherName: session['fullName'] ?? 'Dispatcher',
    );
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _leftCtrl.dispose();
    _rightCtrl.dispose();
    super.dispose();
  }

  void _toggleLeft() {
    setState(() => _leftOpen = !_leftOpen);
    _leftOpen ? _leftCtrl.forward() : _leftCtrl.reverse();
  }

  void _openLeft() {
    if (!_leftOpen) {
      setState(() => _leftOpen = true);
      _leftCtrl.forward();
    }
  }

  void _openRight() {
    if (!_rightOpen) {
      setState(() => _rightOpen = true);
      _rightCtrl.forward();
    }
  }

  void _closeRight() {
    if (_rightOpen) {
      _rightCtrl.reverse().then((_) {
        if (mounted) setState(() => _rightOpen = false);
      });
    }
  }

  void _toggleRight() {
    if (_rightOpen) {
      _closeRight();
    } else {
      setState(() => _rightOpen = true);
      _rightCtrl.forward();
    }
  }

  List<EmergencyReport> _applyFilter(List<EmergencyReport> reports) {
    final active = reports.where((r) {
      final t = r.emergencyType.toLowerCase();
      return t == 'crime' || t == 'accident';
    }).toList();
    if (_statusFilter == 'All') return active;
    return active.where((r) => r.status == _statusFilter).toList();
  }

  Map<String, List<EmergencyReport>> _sortGrouped(
    Map<String, List<EmergencyReport>> grouped,
  ) {
    final entries = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final sorted = <String, List<EmergencyReport>>{};
    for (final e in entries) {
      sorted[e.key] = e.value
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return sorted;
  }

  static const String _oneActiveReportMessage =
      'You already have a dispatched report in progress. Resolve it before '
      'dispatching another.';

  Future<void> _acknowledge(
    String reportId, {
    String reportLabel = 'crime-report',
  }) async {
    final session = await AuthService.getSession();
    if (session == null) return;
    final dispatcherId = session['userId'] ?? '';

    // Cheap client-side pre-check (from the live report cache) so a
    // dispatcher who already has an active report is told immediately,
    // without opening the message dialog first.
    final alreadyActive = _latestReports.any(
      (r) => r.status == 'Acknowledged' && r.dispatcherId == dispatcherId,
    );
    if (alreadyActive) {
      _showSnack(_oneActiveReportMessage, AppColors.pending);
      return;
    }

    final result = await _promptAcknowledgeMessage();
    if (result == null) return; // dispatcher cancelled

    try {
      await _service.acknowledgeReport(
        reportId,
        reportLabel: reportLabel,
        dispatcherId: dispatcherId,
        dispatcherName: session['fullName'] ?? 'Dispatcher',
        dispatcherMessage: result.isEmpty ? null : result,
      );
    } on DispatcherHasActiveReportException {
      // Authoritative backstop — catches races the local cache missed (e.g.
      // the same account dispatching from a second device).
      _showSnack(_oneActiveReportMessage, AppColors.pending);
      return;
    } on ReportAlreadyDispatchedException catch (e) {
      _showSnack(e.toString(), AppColors.pending);
      return;
    }
    _showSnack(
      result.isEmpty
          ? 'Report acknowledged — units dispatched'
          : 'Report acknowledged — message sent to reporter',
      AppColors.acknowledged,
    );
  }

  // Prompts for an optional message to send the reporter along with the
  // acknowledgement. Returns null if the dispatcher cancelled, otherwise the
  // (possibly empty) message text to proceed with.
  Future<String?> _promptAcknowledgeMessage() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.acknowledged),
            const SizedBox(width: 10),
            const Expanded(child: Text('Acknowledge Report')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Units will be dispatched. You can optionally send a message '
              'to the reporter — they\'ll receive it as a notification in '
              'LifeGuard360.',
              style: TextStyle(fontSize: 13, color: AppColors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 200,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Optional message to the reporter…',
                hintStyle: const TextStyle(fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.acknowledged,
            ),
            child: const Text(
              'Acknowledge',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(
    String reportId, {
    String reportLabel = 'crime-report',
  }) async {
    try {
      await _service.resolveReport(reportId, reportLabel: reportLabel);
    } on StateError {
      _showSnack(
        'This report must be dispatched before it can be resolved.',
        AppColors.pending,
      );
      return;
    }
    if (_selectedReport?.reportId == reportId && _statusFilter != 'Resolved') {
      setState(() => _selectedReport = null);
      _closeRight();
    }
    _showSnack('Report marked as resolved ✓', AppColors.resolved);
  }

  Future<bool?> _confirmLogout() {
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.logout, color: AppColors.danger),
            const SizedBox(width: 10),
            const Expanded(child: Text('Exit LifeGuard360?')),
          ],
        ),
        content: const Text(
          'You will be logged out and returned to the login screen. '
          'Any unsaved changes on this screen will be lost.',
          style: TextStyle(fontSize: 13, color: AppColors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Exit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onReportTap(EmergencyReport report) =>
      setState(() => _selectedReport = report);

  void _onViewReport(EmergencyReport report) {
    setState(() {
      _selectedReport = report;
      _leftOpen = false;
    });
    _leftCtrl.reverse();
    _openRight();
  }

  Future<void> _openProfile() async {
    final session = await AuthService.getSession();
    if (session == null) return;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileSettingsScreen(session: session),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await _confirmLogout();
    if (confirmed != true) return;

    final session = await AuthService.getSession();
    if (session != null) {
      await DispatcherFcmService.removeToken(session['userId'] ?? '');
    }
    await AuthService.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          SizedBox(height: topPadding),
          _buildTopBar(),
          Expanded(
            child: StreamBuilder<List<EmergencyReport>>(
              stream: _reportsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }
                final allReports = snapshot.data ?? [];
                final filteredReports = _applyFilter(allReports);
                final rawGrouped = _service.groupByBarangay(
                  filteredReports,
                  includeResolved:
                      _statusFilter == 'Resolved' || _statusFilter == 'All',
                );
                final grouped = _sortGrouped(rawGrouped);

                if (_selectedReport != null) {
                  final match = allReports
                      .where((r) => r.reportId == _selectedReport!.reportId)
                      .toList();
                  if (match.isNotEmpty &&
                      match.first.status != _selectedReport!.status) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted)
                        setState(() => _selectedReport = match.first);
                    });
                  }
                }

                final activeReports = allReports.where((r) {
                  final t = r.emergencyType.toLowerCase();
                  return t == 'crime' || t == 'accident';
                }).toList();
                final pendingCount = activeReports
                    .where((r) => r.status == 'Pending')
                    .length;
                final acknowledgedCount = activeReports
                    .where((r) => r.status == 'Acknowledged')
                    .length;
                final resolvedCount = activeReports
                    .where((r) => r.status == 'Resolved')
                    .length;

                return _buildDashboard(
                  activeReports: activeReports,
                  filteredReports: filteredReports,
                  grouped: grouped,
                  pendingCount: pendingCount,
                  acknowledgedCount: acknowledgedCount,
                  resolvedCount: resolvedCount,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8EDF5))),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.local_police,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LifeGuard360',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2035),
                  ),
                ),
                Text(
                  'PANABO CITY · CRIME DISPATCHER',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
          ),
          _PanelToggleBtn(
            icon: Icons.view_sidebar,
            tooltip: 'Toggle Reports Panel',
            isActive: _leftOpen,
            onTap: _toggleLeft,
          ),
          const SizedBox(width: 6),
          _PanelToggleBtn(
            icon: Icons.view_sidebar_outlined,
            tooltip: 'Toggle Detail Panel',
            isActive: _rightOpen,
            onTap: _toggleRight,
            mirrored: true,
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 28, color: const Color(0xFFE8EDF5)),
          const SizedBox(width: 10),
          _TopIconBtn(
            icon: Icons.person_outline,
            tooltip: 'Profile & Account',
            color: AppColors.primary,
            onTap: _openProfile,
          ),
          const SizedBox(width: 6),
          _TopIconBtn(
            icon: Icons.logout,
            tooltip: 'Logout',
            color: AppColors.danger,
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard({
    required List<EmergencyReport> activeReports,
    required List<EmergencyReport> filteredReports,
    required Map<String, List<EmergencyReport>> grouped,
    required int pendingCount,
    required int acknowledgedCount,
    required int resolvedCount,
  }) {
    return Stack(
      children: [
        // ── MAP ──────────────────────────────────────────────────────────────
        Positioned.fill(
          child: MapPanel(
            reports: activeReports,
            selectedReport: _selectedReport,
            onMarkerTap: _onViewReport,
            pendingCount: pendingCount,
            acknowledgedCount: acknowledgedCount,
            resolvedCount: resolvedCount,
            statusFilter: _statusFilter,
            onFilterChanged: (f) => setState(() => _statusFilter = f),
            leftOpen: _leftOpen,
            rightOpen: _rightOpen,
            onOpenLeftPanel: _openLeft,
          ),
        ),

        // ── LEFT PANEL ───────────────────────────────────────────────────────
        AnimatedBuilder(
          animation: _leftAnim,
          builder: (context, child) => Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: _kPanelWidth * _leftAnim.value,
            child: child!,
          ),
          child: ClipRect(
            child: SizedBox(
              width: _kPanelWidth,
              child: _LeftPanel(
                filters: _filters,
                statusFilter: _statusFilter,
                filteredReports: filteredReports,
                grouped: grouped,
                selectedReportId: _selectedReport?.reportId,
                pendingCount: pendingCount,
                acknowledgedCount: acknowledgedCount,
                resolvedCount: resolvedCount,
                onFilterChanged: (f) => setState(() => _statusFilter = f),
                onReportTap: _onReportTap,
                onAcknowledge: (id, {reportLabel = 'crime-report'}) =>
                    _acknowledge(id, reportLabel: reportLabel),
                onResolve: (id, {reportLabel = 'crime-report'}) =>
                    _resolve(id, reportLabel: reportLabel),
                onViewReport: _onViewReport,
              ),
            ),
          ),
        ),

        // ── LEFT EDGE TAB ────────────────────────────────────────────────────
        AnimatedPositioned(
          duration: _kPanelDuration,
          curve: _kPanelCurve,
          left: _leftOpen ? _kPanelWidth : 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: _EdgeTab(
              icon: _leftOpen ? Icons.chevron_left : Icons.chevron_right,
              tooltip: _leftOpen ? 'Hide Reports' : 'Show Reports',
              onTap: _toggleLeft,
              side: _EdgeTabSide.left,
            ),
          ),
        ),

        // ── RIGHT DETAIL PANEL ───────────────────────────────────────────────
        AnimatedBuilder(
          animation: _rightAnim,
          builder: (context, child) => Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: _kPanelWidth * _rightAnim.value,
            child: child!,
          ),
          child: ClipRect(
            child: SizedBox(
              width: _kPanelWidth,
              child: _RightPanel(
                report: _selectedReport,
                onClose: () {
                  setState(() => _selectedReport = null);
                  _closeRight();
                },
                onAcknowledge: _selectedReport != null
                    ? () => _acknowledge(
                        _selectedReport!.reportId,
                        reportLabel: _selectedReport!.reportLabel,
                      )
                    : null,
                onResolve: _selectedReport != null
                    ? () => _resolve(
                        _selectedReport!.reportId,
                        reportLabel: _selectedReport!.reportLabel,
                      )
                    : null,
              ),
            ),
          ),
        ),

        // ── RIGHT EDGE TAB ───────────────────────────────────────────────────
        AnimatedPositioned(
          duration: _kPanelDuration,
          curve: _kPanelCurve,
          right: _rightOpen ? _kPanelWidth : 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: _EdgeTab(
              icon: _rightOpen ? Icons.chevron_right : Icons.chevron_left,
              tooltip: _rightOpen ? 'Hide Details' : 'Show Details',
              onTap: _toggleRight,
              side: _EdgeTabSide.right,
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LEFT PANEL
// ══════════════════════════════════════════════════════════════════════════════
class _LeftPanel extends StatelessWidget {
  final List<String> filters;
  final String statusFilter;
  final List<EmergencyReport> filteredReports;
  final Map<String, List<EmergencyReport>> grouped;
  final String? selectedReportId;
  final int pendingCount;
  final int acknowledgedCount;
  final int resolvedCount;
  final ValueChanged<String> onFilterChanged;
  final Function(EmergencyReport) onReportTap;
  final Function(String, {String reportLabel}) onAcknowledge;
  final Function(String, {String reportLabel}) onResolve;
  final Function(EmergencyReport) onViewReport;

  const _LeftPanel({
    required this.filters,
    required this.statusFilter,
    required this.filteredReports,
    required this.grouped,
    required this.selectedReportId,
    required this.pendingCount,
    required this.acknowledgedCount,
    required this.resolvedCount,
    required this.onFilterChanged,
    required this.onReportTap,
    required this.onAcknowledge,
    required this.onResolve,
    required this.onViewReport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE8EDF5))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 12,
            offset: Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FA),
              border: Border(bottom: BorderSide(color: Color(0xFFE8EDF5))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'ACTIVE REPORTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2035),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.pending.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.pending.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        '${filteredReports.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.pending,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStatChip(
                        count: pendingCount,
                        label: 'Pending',
                        color: AppColors.pending,
                        isSelected: statusFilter == 'Pending',
                        onTap: () => onFilterChanged(
                          statusFilter == 'Pending' ? 'All' : 'Pending',
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: _MiniStatChip(
                        count: acknowledgedCount,
                        label: 'Dispatched',
                        color: AppColors.acknowledged,
                        isSelected: statusFilter == 'Acknowledged',
                        onTap: () => onFilterChanged(
                          statusFilter == 'Acknowledged'
                              ? 'All'
                              : 'Acknowledged',
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: _MiniStatChip(
                        count: resolvedCount,
                        label: 'Resolved',
                        color: AppColors.resolved,
                        isSelected: statusFilter == 'Resolved',
                        onTap: () => onFilterChanged(
                          statusFilter == 'Resolved' ? 'All' : 'Resolved',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: const Color(0xFFF8F9FA),
            child: Row(
              children: filters
                  .map(
                    (f) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: GestureDetector(
                          onTap: () => onFilterChanged(f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: statusFilter == f
                                  ? AppColors.primary
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: statusFilter == f
                                    ? AppColors.primary
                                    : const Color(0xFFDDE1E8),
                              ),
                            ),
                            child: Text(
                              f,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: statusFilter == f
                                    ? Colors.white
                                    : AppColors.grey,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: filteredReports.isEmpty
                ? _EmptyList(filter: statusFilter)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 70),
                    children: grouped.entries
                        .map(
                          (entry) => BarangayGroup(
                            key: ValueKey(entry.key),
                            barangayName: entry.key,
                            reports: entry.value,
                            selectedReportId: selectedReportId,
                            onReportTap: onReportTap,
                            onAcknowledge: onAcknowledge,
                            onResolve: onResolve,
                            onViewReport: onViewReport,
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MINI STAT CHIP
// ══════════════════════════════════════════════════════════════════════════════
class _MiniStatChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isSelected;

  const _MiniStatChip({
    required this.count,
    required this.label,
    required this.color,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isSelected ? 'Show all reports' : 'Filter by $label',
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.18)
                : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.2),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  final String filter;
  const _EmptyList({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🚨', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(
            filter == 'All' ? 'No active reports' : 'No $filter reports',
            style: const TextStyle(
              color: AppColors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Reports appear here in real-time',
            style: TextStyle(color: AppColors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RIGHT PANEL
// ══════════════════════════════════════════════════════════════════════════════
class _RightPanel extends StatelessWidget {
  final EmergencyReport? report;
  final VoidCallback? onClose;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onResolve;

  const _RightPanel({
    required this.report,
    this.onClose,
    this.onAcknowledge,
    this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE8EDF5))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 12,
            offset: Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: report != null
                  ? report!.typeColor.withValues(alpha: 0.05)
                  : const Color(0xFFF8F9FA),
              border: const Border(
                bottom: BorderSide(color: Color(0xFFE8EDF5)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: (report?.typeColor ?? AppColors.primary).withValues(
                      alpha: 0.12,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    report != null
                        ? Icons.description_rounded
                        : Icons.info_outline,
                    size: 14,
                    color: report?.typeColor ?? AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'REPORT DETAILS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A2035),
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        report != null
                            ? '${report!.emergencyType} · ${report!.status}'
                            : 'No report selected',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (report != null && onClose != null)
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 15,
                        color: AppColors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.03),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: report == null
                  ? const _RightPlaceholder(key: ValueKey('placeholder'))
                  : ReportDetailPanel(
                      key: ValueKey(report!.reportId),
                      report: report,
                      onAcknowledge: onAcknowledge,
                      onResolve: onResolve,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RightPlaceholder extends StatelessWidget {
  const _RightPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.14),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.touch_app_outlined,
              size: 32,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No Report Selected',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A2035),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap "View Report" on any card, or\ntap a map marker to open details here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.grey, height: 1.6),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EDF5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'STATUS GUIDE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.grey,
                  ),
                ),
                const SizedBox(height: 10),
                _GuideRow(
                  color: AppColors.pending,
                  icon: Icons.pending_outlined,
                  text: 'Pending — Awaiting response',
                ),
                _GuideRow(
                  color: AppColors.acknowledged,
                  icon: Icons.directions_run,
                  text: 'Acknowledged — Units en route',
                ),
                _GuideRow(
                  color: AppColors.resolved,
                  icon: Icons.task_alt,
                  text: 'Resolved — Incident closed',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _GuideRow({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, color: AppColors.darkGrey),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EDGE TAB
// ══════════════════════════════════════════════════════════════════════════════
enum _EdgeTabSide { left, right }

class _EdgeTab extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final _EdgeTabSide side;

  const _EdgeTab({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.side,
  });

  @override
  State<_EdgeTab> createState() => _EdgeTabState();
}

class _EdgeTabState extends State<_EdgeTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isLeft = widget.side == _EdgeTabSide.left;
    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _hovered ? 22 : 18,
            height: 56,
            decoration: BoxDecoration(
              color: _hovered ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isLeft ? 0 : 8),
                bottomLeft: Radius.circular(isLeft ? 0 : 8),
                topRight: Radius.circular(isLeft ? 8 : 0),
                bottomRight: Radius.circular(isLeft ? 8 : 0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _hovered ? 0.15 : 0.08),
                  blurRadius: _hovered ? 10 : 6,
                  offset: isLeft ? const Offset(2, 0) : const Offset(-2, 0),
                ),
              ],
              border: Border.all(
                color: _hovered ? AppColors.primary : const Color(0xFFDDE1E8),
              ),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _hovered ? Colors.white : AppColors.grey,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════
class _PanelToggleBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;
  final bool mirrored;

  const _PanelToggleBtn({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
    this.mirrored = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : const Color(0xFFE0E4EA),
            ),
          ),
          child: Transform(
            transform: mirrored
                ? (Matrix4.identity()..scale(-1.0, 1.0, 1.0))
                : Matrix4.identity(),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 16,
              color: isActive ? AppColors.primary : AppColors.grey,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _TopIconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}
