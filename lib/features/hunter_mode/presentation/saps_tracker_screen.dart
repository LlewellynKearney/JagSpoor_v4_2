import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../ballistics/data/models/saps_application_model.dart';
import '../../hunter_mode/models/saps_tracking_details.dart';
import '../../hunter_mode/services/saps_sms_parser.dart';
import '../../hunter_mode/services/saps_tracker_service.dart';
import '../../../core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';
import 'package:jagspoor/features/shared/widgets/hunter_media_card.dart';

/// SAPS License & Competency Application Tracker Screen.
/// Provides a dashboard for registering and monitoring firearm license
/// and competency application statuses.
class SapsTrackerScreen extends StatefulWidget {
  const SapsTrackerScreen({super.key});

  @override
  State<SapsTrackerScreen> createState() => _SapsTrackerScreenState();
}

class _SapsTrackerScreenState extends State<SapsTrackerScreen> {
  final _idNumberController = TextEditingController();
  final _referenceController = TextEditingController();
  final _smsController = TextEditingController();
  final _calibreController = TextEditingController();
  final _serialNumberController = TextEditingController();
  String _selectedApplicationType = SapsApplication.applicationTypes.first;
  bool _isLoading = false;
  bool _isRefreshingAll = false;

  final SapsTrackerService _trackerService = SapsTrackerService();

  @override
  void dispose() {
    _idNumberController.dispose();
    _referenceController.dispose();
    _smsController.dispose();
    _calibreController.dispose();
    _serialNumberController.dispose();
    super.dispose();
  }

  /// Resolves the signed-in user id, degrading to null when Firebase Auth is
  /// unavailable (cold-launch race / widget-test env) so the screen renders
  /// the "log in" empty state instead of crashing with `[core/no-app]`.
  String? get _currentUserId {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Parses the pasted SAPS notification SMS and pre-populates the
  /// registration form fields, then lets the user review before registering.
  void _parseSmsMessage() {
    final raw = _smsController.text;
    if (raw.trim().isEmpty) {
      _showErrorSnackBar('Paste a SAPS notification SMS first');
      return;
    }

    final result = SapsSmsParser.parse(raw);

    if (!result.hasAnyField) {
      _showErrorSnackBar(
        'No application details recognised. Expected a SAPS notification '
        'SMS containing an application reference, calibre, or serial number.',
      );
      return;
    }

    setState(() {
      if (result.hasReference) {
        _referenceController.text = result.referenceNumber;
      }
      // Only override the type when the parser inferred a specific one (the
      // default "Competency Certificate" is the fallback, not a signal).
      if (result.applicationType != 'Competency Certificate') {
        _selectedApplicationType = result.applicationType;
      }
      if (result.calibre.isNotEmpty) {
        _calibreController.text = result.calibre;
      }
      if (result.serialNumber.isNotEmpty) {
        _serialNumberController.text = result.serialNumber;
      }
    });

    final details = <String>[
      if (result.hasReference) 'Reference: ${result.referenceNumber}',
      if (result.calibre.isNotEmpty) 'Calibre: ${result.calibre}',
      if (result.serialNumber.isNotEmpty) 'S/N: ${result.serialNumber}',
      if (result.hasStatus) 'Status: ${result.statusMessage}',
    ];

    final message =
        'Details found → ${details.join(' · ')}. Review the fields below '
        'before registering.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 6),
        ),
      );
  }

  Future<void> _registerApplication() async {
    if (_currentUserId == null) {
      _showErrorSnackBar('Please log in to track applications');
      return;
    }

    final idNumber = _idNumberController.text.trim();
    final referenceNumber = _referenceController.text.trim();
    final calibre = _calibreController.text.trim();
    final serialNumber = _serialNumberController.text.trim();

    if (idNumber.isEmpty) {
      _showErrorSnackBar('Please enter your ID Number');
      return;
    }

    if (referenceNumber.isEmpty) {
      _showErrorSnackBar('Please enter the Application Reference Code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();
      final docRef = await firestore.collection('license_applications').add({
        'hunterId': _currentUserId,
        'referenceNumber': referenceNumber,
        'idNumber': idNumber,
        'applicationType': _selectedApplicationType,
        'currentStatus': 'Submitted',
        'calibre': calibre,
        'serialNumber': serialNumber,
        'submittedAt': now.toIso8601String(),
        'lastChecked': now.toIso8601String(),
      });

      if (mounted) {
        _idNumberController.clear();
        _referenceController.clear();
        _smsController.clear();
        _calibreController.clear();
        _serialNumberController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Application registered: ${docRef.id}'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to register: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Manual refresh: force-reloads status data for every tracked application.
  Future<void> _manualRefresh() async {
    if (_currentUserId == null || _isRefreshingAll) return;

    setState(() => _isRefreshingAll = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final refreshed = await _trackerService.refreshAllApplications();
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                refreshed > 0
                    ? 'Status refreshed for $refreshed application${refreshed == 1 ? '' : 's'}'
                    : 'No applications could be refreshed',
              ),
              backgroundColor: refreshed > 0
                  ? Colors.green.shade700
                  : Colors.orange.shade800,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingAll = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hunterTheme = ThemeController.instance;

    return HunterScaffold(
      theme: hunterTheme,
      padBodyForAppBar: true,
      appBar: AppBar(
        title: Text(
          '💳 SAPS Tracker',
          style: TextStyle(
            color: HunterUi.titleColor(hunterTheme),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: HunterUi.titleColor(hunterTheme)),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable top section (register form + tracked header) so the input
            // card scrolls on short screens instead of overflowing the body.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Input Block
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        color: HunterUi.cardColor(hunterTheme),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'REGISTER APPLICATION',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // SMS Paste Input
                              TextField(
                                controller: _smsController,
                                maxLines: 3,
                                minLines: 2,
                                decoration: InputDecoration(
                                  labelText: 'Paste SAPS Notification SMS',
                                  hintText:
                                      'e.g., SAPS msg: Application Ref. 10470664 for calibre 6MM MUSGRAVE s/n OB14468',
                                  alignLabelWithHint: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: const Icon(Icons.sms_outlined),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Parse SMS Button
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _parseSmsMessage,
                                  icon:
                                      const Icon(Icons.auto_fix_high, size: 18),
                                  label: const Text(
                                    'Extract Details from SMS',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // ID Number Input
                              TextField(
                                controller: _idNumberController,
                                decoration: InputDecoration(
                                  labelText: 'ID Number',
                                  hintText: 'Enter your 13-digit SA ID',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: const Icon(Icons.badge_outlined),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 12),
                              // Reference Number Input
                              TextField(
                                controller: _referenceController,
                                decoration: InputDecoration(
                                  labelText: 'Application Reference Code',
                                  hintText: 'Parsed from SMS if available',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: const Icon(Icons.tag),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Calibre Input (parsed from SMS or manual)
                              TextField(
                                controller: _calibreController,
                                decoration: InputDecoration(
                                  labelText: 'Calibre',
                                  hintText:
                                      'Parsed from SMS, e.g., 6MM MUSGRAVE',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: const Icon(Icons.gps_fixed),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Serial Number Input (parsed from SMS or manual)
                              TextField(
                                controller: _serialNumberController,
                                decoration: InputDecoration(
                                  labelText: 'Serial Number',
                                  hintText: 'Parsed from SMS, e.g., OB14468',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: const Icon(Icons.numbers),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Application Type Dropdown
                              DropdownButtonFormField<String>(
                                value: _selectedApplicationType,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Application Type',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon:
                                      const Icon(Icons.category_outlined),
                                ),
                                items: SapsApplication.applicationTypes
                                    .map(
                                      (typeString) => DropdownMenuItem(
                                        value: typeString,
                                        child: Text(
                                          typeString,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(
                                        () => _selectedApplicationType = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              // Register Button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed:
                                      _isLoading ? null : _registerApplication,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor:
                                        theme.colorScheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Register Application for Tracking',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Active Tracker Grid View
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'TRACKED APPLICATIONS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.secondary,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          // Manual Refresh Button
                          IconButton(
                            tooltip: 'Refresh all statuses',
                            onPressed: _isRefreshingAll ? null : _manualRefresh,
                            icon: _isRefreshingAll
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(
                                    Icons.refresh,
                                    color: theme.colorScheme.primary,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // StreamBuilder for active applications
            Expanded(
              child: _currentUserId == null
                  ? Center(
                      child: Text(
                        'Please log in to view tracked applications',
                        style: TextStyle(color: theme.hintColor),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('license_applications')
                          .where('hunterId', isEqualTo: _currentUserId)
                          .orderBy('lastChecked', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Error loading applications: ${snapshot.error}',
                              style: TextStyle(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inbox_outlined,
                                  size: 64,
                                  color: theme.hintColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No applications tracked yet',
                                  style: TextStyle(color: theme.hintColor),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Register your first application above',
                                  style: TextStyle(
                                    color: theme.hintColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final app = SapsApplication.fromFirestore(
                              docs[index]
                                  as DocumentSnapshot<Map<String, dynamic>>,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SapsApplicationCard(
                                application: app,
                                trackerService: _trackerService,
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card widget displaying a single tracked application with stage progress
/// bar and an expandable detailed view.
class SapsApplicationCard extends StatefulWidget {
  final SapsApplication application;
  final SapsTrackerService trackerService;

  const SapsApplicationCard({
    super.key,
    required this.application,
    required this.trackerService,
  });

  @override
  State<SapsApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends State<SapsApplicationCard> {
  bool _expanded = false;
  bool _refreshing = false;
  SapsTrackingDetails? _details;
  bool _detailsLoaded = false;

  SapsApplication get application => widget.application;

  Future<void> _toggleExpanded() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && !_detailsLoaded) {
      await _loadDetails();
    }
  }

  Future<void> _loadDetails() async {
    final details = await widget.trackerService.fetchTrackingDetails(
      application.id,
    );
    if (mounted) {
      setState(() {
        _details = details;
        _detailsLoaded = true;
      });
    }
  }

  Future<void> _refreshSingle() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.trackerService.refreshApplication(
        application.id,
      );
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: result.success
                  ? Colors.green.shade700
                  : Colors.orange.shade800,
            ),
          );
        // Re-fetch the expanded details so the timeline reflects the refresh.
        if (_expanded) {
          await _loadDetails();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hunterTheme = ThemeController.instance;
    final now = DateTime.now();

    return Card(
      color: HunterUi.cardColor(hunterTheme),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _toggleExpanded,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      application.applicationType,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      application.currentStatus,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Prominent submission date milestone.
              Row(
                children: [
                  Icon(
                    Icons.event_available,
                    size: 15,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      application.submittedAt != null
                          ? 'Submitted: ${_formatDateOnly(application.submittedAt!)}'
                          : 'Submitted: not recorded',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Ref: ${application.referenceNumber}',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
              const SizedBox(height: 10),
              // Firearm details + working-day milestone tallies as pills.
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (application.calibre.isNotEmpty)
                    HunterDataPill(
                      theme: hunterTheme,
                      pill: HunterMediaPill(
                        icon: Icons.gps_fixed,
                        label: application.calibre,
                        amber: true,
                      ),
                    ),
                  if (application.serialNumber.isNotEmpty)
                    HunterDataPill(
                      theme: hunterTheme,
                      pill: HunterMediaPill(
                        icon: Icons.pin_outlined,
                        label: 's/n ${application.serialNumber}',
                      ),
                    ),
                  if (application.workingDaysSinceSubmitted(now) != null)
                    HunterDataPill(
                      theme: hunterTheme,
                      pill: HunterMediaPill(
                        icon: Icons.work_outline,
                        label:
                            '${application.workingDaysSinceSubmitted(now)} workdays since submission',
                        amber: true,
                      ),
                    ),
                  if (application.workingDaysSinceProvincialDfo(now) != null)
                    HunterDataPill(
                      theme: hunterTheme,
                      pill: HunterMediaPill(
                        icon: Icons.account_balance_outlined,
                        label:
                            '${application.workingDaysSinceProvincialDfo(now)} workdays at provincial DFO',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Stage Progress Tracker Bar
              _StageProgressBar(
                currentStage: application.stageIndex,
                stages: SapsApplication.statusStages,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Last checked: ${_formatDate(application.lastChecked)}',
                      style: TextStyle(fontSize: 11, color: theme.hintColor),
                    ),
                  ),
                  // Per-card manual refresh
                  IconButton(
                    tooltip: 'Refresh this application',
                    onPressed: _refreshing ? null : _refreshSingle,
                    icon: _refreshing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.refresh,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                  ),
                  // Expand / collapse toggle
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              // Expandable detailed view
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity),
                secondChild: _buildExpandedDetails(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Comprehensive tracking details pulled from the tracking system:
  /// status timeline, waiting-period estimates, batch details, and the current
  /// progress stage.
  Widget _buildExpandedDetails(ThemeData theme) {
    if (!_detailsLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final details = _details;
    if (details == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Tracking details are not available for this application.',
          style: TextStyle(fontSize: 12, color: theme.hintColor),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        _sectionTitle(theme, 'CURRENT PROGRESS'),
        const SizedBox(height: 8),
        _detailRow(
          theme,
          Icons.track_changes,
          details.currentProgressLabel ?? application.currentStatus,
          details.currentProgressDetail,
        ),
        if (details.timeline.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle(theme, 'STATUS TIMELINE'),
          const SizedBox(height: 8),
          ...details.timeline.map(
            (entry) => _timelineRow(theme, entry),
          ),
        ],
        if (details.waitingEstimates.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle(theme, 'ESTIMATED WAITING PERIODS'),
          const SizedBox(height: 8),
          ...details.waitingEstimates.map(
            (estimate) => _estimateRow(theme, estimate),
          ),
        ],
        if (details.batches.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle(theme, 'BATCH DETAILS'),
          const SizedBox(height: 8),
          ...details.batches.map(
            (batch) => _batchRow(theme, batch),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Refreshed: ${details.refreshedAt != null ? _formatDate(details.refreshedAt!) : _formatDate(application.lastChecked)}',
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.secondary,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _detailRow(
    ThemeData theme,
    IconData icon,
    String label,
    String? detail,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (detail != null && detail.isNotEmpty)
                Text(
                  detail,
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timelineRow(ThemeData theme, SapsStatusTimelineEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 10, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (entry.timestamp != null)
                  Text(
                    _formatDate(entry.timestamp!),
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
                if (entry.detail != null && entry.detail!.isNotEmpty)
                  Text(
                    entry.detail!,
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _estimateRow(ThemeData theme, SapsWaitingEstimate estimate) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${estimate.stageLabel}: ${estimate.estimate}',
              style:
                  TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _batchRow(ThemeData theme, SapsBatchDetail batch) {
    final parts = <String>[
      if (batch.batchNumber.isNotEmpty) 'Batch ${batch.batchNumber}',
      if (batch.applicationCount != null)
        '${batch.applicationCount} application${batch.applicationCount == 1 ? '' : 's'}',
      if (batch.status != null && batch.status!.isNotEmpty) batch.status!,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.inventory_2, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parts.isEmpty ? 'Batch' : parts.join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (batch.submittedAt != null)
                  Text(
                    'Submitted: ${_formatDate(batch.submittedAt!)}',
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Compact date-only formatter (e.g. `12 Mar 2026`) for the prominent
  /// submission-date milestone on the collapsed card.
  String _formatDateOnly(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

/// Horizontal stage progress bar for tracking application status.
class _StageProgressBar extends StatelessWidget {
  final int currentStage;
  final List<String> stages;

  const _StageProgressBar({required this.currentStage, required this.stages});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: List.generate(stages.length * 2 - 1, (index) {
        if (index.isOdd) {
          // Connector line
          final stageIndex = index ~/ 2;
          final isCompleted = stageIndex < currentStage;
          return Expanded(
            child: Container(
              height: 3,
              color: isCompleted
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          );
        } else {
          // Stage node
          final stageIndex = index ~/ 2;
          final isCompleted = stageIndex <= currentStage;
          return Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withValues(alpha: 0.3),
              border: Border.all(color: theme.colorScheme.primary, width: 2),
            ),
            child: Center(
              child: Text(
                '${stageIndex + 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isCompleted
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          );
        }
      }),
    );
  }
}
