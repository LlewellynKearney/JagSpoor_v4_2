import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../ballistics/data/models/saps_application_model.dart';
import '../../hunter_mode/models/saps_tracking_details.dart';
import '../../hunter_mode/services/saps_cfr_scraper_client.dart';
import '../../hunter_mode/services/saps_sms_parser.dart';
import '../../hunter_mode/services/saps_status_classifier.dart';
import '../../hunter_mode/services/saps_tracker_service.dart';
import '../../firearm_safe/data/models/firearm.dart';
import '../../firearm_safe/data/services/firearm_safe_repository.dart';
import '../../../core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';
import 'package:jagspoor/features/hunter_mode/firearm_safe_screen.dart';
import 'package:jagspoor/features/shared/widgets/hunter_media_card.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';

/// SAPS License & Competency Application Tracker Screen.
/// Provides a dashboard for registering and monitoring firearm license
/// and competency application statuses.
class SapsTrackerScreen extends StatefulWidget {
  /// Test seam: overrides the CFR enquiry client factory so the result-card
  /// states (loading / NEED_SERIAL / NOT_FOUND / full result / approved) can
  /// be widget-tested with a mocked transport and no live network. Defaults
  /// to a real [SapsCfrScraperClient] (webhook in production, direct portal
  /// path in a debug build).
  @visibleForTesting
  final SapsCfrScraperClient Function()? enquiryClientFactory;

  const SapsTrackerScreen({super.key, this.enquiryClientFactory});

  @override
  State<SapsTrackerScreen> createState() => _SapsTrackerScreenState();
}

class _SapsTrackerScreenState extends State<SapsTrackerScreen> {
  final _idNumberController = TextEditingController();
  final _referenceController = TextEditingController();
  final _smsController = TextEditingController();
  final _makeController = TextEditingController();
  final _calibreController = TextEditingController();
  final _serialNumberController = TextEditingController();

  /// Live CFR enquiry inputs (the 6-field reference + serial POST). Kept
  /// separate from the registration form so a hunter can look up ANY
  /// reference without first creating a tracked application.
  final _enquiryRefController = TextEditingController();
  final _enquirySerialController = TextEditingController();

  String _selectedApplicationType = SapsApplication.applicationTypes.first;
  bool _isLoading = false;
  bool _isRefreshingAll = false;
  bool _registerExpanded = false;

  /// Live-enquiry state.
  bool _enquiryRunning = false;
  String? _enquiryError;
  SapsCfrStatus? _enquiryResult;
  bool _enquiryPayloadExpanded = false;

  final SapsTrackerService _trackerService = SapsTrackerService();
  final FirearmSafeRepository _safeRepository = FirearmSafeRepository();

  /// Adds the approved firearm from the current live-enquiry result to the
  /// Digital Firearm Safe (de-duplicated by serial). Returns true when a
  /// firearm was added (false when it already existed / nothing to add).
  Future<bool> _addEnquiryResultToSafe(SapsCfrStatus result) async {
    final firearm = Firearm.fromSaps(
      make: result.make,
      calibre: result.calibre,
      serial: result.serialNumber,
      appNo: result.applicationNumber,
      type: result.applicationType,
      status: result.rawStatus,
      statusDate: result.statusDate,
      rawPayload: result.raw,
    );
    if (await _safeRepository.existsBySerial(firearm.serial)) {
      return false;
    }
    final id = await _safeRepository.addFirearm(firearm);
    return id != null;
  }

  @override
  void dispose() {
    _idNumberController.dispose();
    _referenceController.dispose();
    _smsController.dispose();
    _makeController.dispose();
    _calibreController.dispose();
    _serialNumberController.dispose();
    _enquiryRefController.dispose();
    _enquirySerialController.dispose();
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

  /// Runs the live CFR enquiry (the 6-field reference + serial POST against
  /// the official portal in a debug build, or the configured webhook in
  /// production) and renders the result card.
  Future<void> _runEnquiry() async {
    final ref = _enquiryRefController.text.trim();
    final serial = _enquirySerialController.text.trim();
    if (ref.isEmpty && serial.isEmpty) {
      setState(() {
        _enquiryError = 'Enter a Reference Number (and Serial Number for '
            'firearm applications).';
        _enquiryResult = null;
      });
      return;
    }

    setState(() {
      _enquiryRunning = true;
      _enquiryError = null;
      _enquiryResult = null;
    });

    try {
      final client =
          widget.enquiryClientFactory?.call() ?? SapsCfrScraperClient();
      final result = await client.fetchStatus(
        referenceNumber: ref,
        idNumber: '',
        serialNumber: serial,
      );
      if (!mounted) return;
      setState(() {
        _enquiryRunning = false;
        _enquiryResult = result;
        _enquiryError = result == null
            ? 'No response parsed. Check connectivity and try again.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enquiryRunning = false;
        _enquiryError = 'Enquiry failed: $e';
      });
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
      if (result.firearmMake.isNotEmpty) {
        _makeController.text = result.firearmMake;
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
      if (result.firearmMake.isNotEmpty) 'Make: ${result.firearmMake}',
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
    final make = _makeController.text.trim();
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
        // Dual-stamp the make under the canonical key + the `make` alias so
        // legacy readers resolve it regardless of spelling.
        'firearmMake': make,
        'make': make,
        'calibre': calibre,
        'serialNumber': serialNumber,
        'submittedAt': now.toIso8601String(),
        'createdAt': now.toIso8601String(),
        'lastChecked': now.toIso8601String(),
      });

      if (mounted) {
        _idNumberController.clear();
        _referenceController.clear();
        _smsController.clear();
        _makeController.clear();
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

  // ---------------------------------------------------------------------------
  // Live CFR enquiry panel + result card
  // ---------------------------------------------------------------------------

  /// The live "Check Status" panel: reference (required) + serial (required
  /// for firearm applications, optional for competency), the hint, and the
  /// ENQUIRE action. Uses the same 6-field scraper client as the debug
  /// screen, so a debug build queries the real portal and a release build
  /// uses the configured webhook.
  Widget _buildEnquiryPanel(ThemeData theme, ThemeController hunterTheme) {
    return Card(
      color: HunterUi.cardColor(hunterTheme),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.travel_explore, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CHECK LIVE STATUS',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: HunterUi.titleColor(hunterTheme),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _enquiryRefController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Reference Number',
                hintText: 'e.g. 10654672',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.tag),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _enquirySerialController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Firearm Serial Number',
                hintText: 'e.g. F004574',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.hintColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'For firearm renewal: enter BOTH Ref + Serial. '
                    'For competency: Ref only.',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _enquiryRunning ? null : _runEnquiry,
              icon: _enquiryRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_enquiryRunning ? 'ENQUIRING…' : 'ENQUIRE'),
            ),
            if (_enquiryError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                ),
                child: Text(
                  _enquiryError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
            if (_enquiryResult != null)
              _buildEnquiryResult(theme, _enquiryResult!),
          ],
        ),
      ),
    );
  }

  /// The live-enquiry result card. Branches on the classified stage:
  ///   * NEED_SERIAL_AND_REF (-2) -> amber "enter both" banner;
  ///   * NOT_FOUND (-1) -> grey "no records" card + collapsed HTML snippet;
  ///   * stage >= 0 -> the full result card (RAW / STAGE / LABEL / UPDATED /
  ///     NOT FOUND / TYPE / APP NO / CALIBRE / MAKE / SERIAL / STATUS DATE /
  ///     DESCRIPTION / NEXT STEP + the collapsible raw payload), plus the
  ///     "Add to Digital Firearm Safe" action when the status is approved.
  Widget _buildEnquiryResult(ThemeData theme, SapsCfrStatus result) {
    if (result.stage == kSapsStageNeedSerialAndRef) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
        ),
        child: Text(
          'Enter both Serial + Reference for firearm apps '
          '(Ref only for competency)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      );
    }

    if (result.stage == kSapsStageNotFound || result.notFound) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.hintColor.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search_off, color: theme.hintColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No records to retrieve for your selected Reference '
                    'Number (REF) and Serial Number (SERIAL)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            if (result.htmlSnippet.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildHtmlSnippet(theme, result.htmlSnippet),
            ],
          ],
        ),
      );
    }

    // stage >= 0 -> the full result card.
    final approved = SapsStatusClassifier.isApproved(result.rawStatus);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESULT',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: HunterUi.titleColor(ThemeController.instance),
              ),
            ),
            const Divider(height: 20),
            _resultRow(theme, 'RAW', result.rawStatus),
            _resultRow(theme, 'STAGE', result.stage.toString()),
            _resultRow(theme, 'LABEL', result.displayLabel),
            _resultRow(
              theme,
              'UPDATED',
              result.sapsUpdatedAt != null
                  ? _formatIsoDate(result.sapsUpdatedAt!)
                  : '—',
            ),
            _resultRow(theme, 'NOT FOUND', result.notFound ? 'true' : 'false'),
            if (result.applicationType.isNotEmpty)
              _resultRow(theme, 'TYPE', result.applicationType),
            if (result.applicationNumber.isNotEmpty)
              _resultRow(theme, 'APP NO', result.applicationNumber),
            if (result.calibre.isNotEmpty)
              _resultRow(theme, 'CALIBRE', result.calibre),
            if (result.make.isNotEmpty)
              _resultRow(theme, 'MAKE', result.make),
            if (result.serialNumber.isNotEmpty)
              _resultRow(theme, 'SERIAL', result.serialNumber),
            if (result.statusDate.isNotEmpty)
              _resultRow(theme, 'STATUS DATE', result.statusDate),
            if (result.statusDescription.isNotEmpty)
              _resultRow(theme, 'DESCRIPTION', result.statusDescription),
            if (result.nextStep.isNotEmpty)
              _resultRow(theme, 'NEXT STEP', result.nextStep),
            if (approved) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _importToSafe(result),
                  icon: const Icon(Icons.shield),
                  label: const Text(
                    'Add to Digital Firearm Safe',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
            if (result.raw != null) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(
                  () => _enquiryPayloadExpanded = !_enquiryPayloadExpanded,
                ),
                child: Row(
                  children: [
                    Icon(
                      _enquiryPayloadExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'RAW PAYLOAD',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_enquiryPayloadExpanded) ...[
                const SizedBox(height: 6),
                SelectableText(
                  result.raw.toString(),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Collapsible first-500-char portal HTML snippet (diagnostics for the
  /// NOT_FOUND card).
  Widget _buildHtmlSnippet(ThemeData theme, String snippet) {
    // Wrap in a transparent Material: the ExpansionTile renders a ListTile,
    // and the NOT_FOUND card's coloured Container ancestor would otherwise
    // trip Flutter's "ListTile ink splashes may be invisible" assertion.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text(
            'PORTAL HTML SNIPPET (first 500 chars)',
            style: TextStyle(fontSize: 11, color: theme.hintColor),
          ),
          children: [
            SelectableText(snippet, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  /// Handles the "Add to Digital Firearm Safe" tap: skips when the serial
  /// already exists, otherwise adds the firearm, surfaces the result, and
  /// navigates into the Digital Firearm Safe so the hunter sees it land.
  Future<void> _importToSafe(SapsCfrStatus result) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final label = [
      result.make,
      result.calibre,
      if (result.serialNumber.isNotEmpty) '(${result.serialNumber})',
    ].where((s) => s.isNotEmpty).join(' ');
    try {
      final added = await _addEnquiryResultToSafe(result);
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              added
                  ? 'Added $label to Safe'
                  : '$label is already in your Digital Firearm Safe',
            ),
            backgroundColor:
                added ? Colors.green.shade700 : Colors.orange.shade800,
          ),
        );
      if (added) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) =>
                FirearmSafeScreen(theme: ThemeController.instance),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Failed to add to Safe: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
    }
  }

  Widget _resultRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: theme.hintColor,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ISO date (e.g. `2026-10-10`) for the portal UPDATED row.
  String _formatIsoDate(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }


  /// Collapsible "Register New Application" accordion. Collapsed by default so
  /// tracked applications dominate the screen; tapping the header expands the
  /// full registration form (with the prominent SMS Quick Add box at the top).
  Widget _buildRegisterAccordion(ThemeData theme, ThemeController hunterTheme) {
    return Card(
      color: HunterUi.cardColor(hunterTheme),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _registerExpanded = !_registerExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _registerExpanded
                          ? Icons.expand_less
                          : Icons.add_circle_outline,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Register New Application',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: HunterUi.titleColor(hunterTheme),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _registerExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _registerExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _buildRegisterForm(theme),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// The full registration form body, headed by the prominent "Paste SAPS
  /// SMS / Quick Add" box that instantly parses reference / calibre / serial
  /// (and make when present) details into the fields below.
  Widget _buildRegisterForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        // Prominent Quick Add box.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Paste SAPS SMS / Quick Add',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _smsController,
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(
                  labelText: 'Paste SAPS Notification SMS',
                  hintText:
                      'e.g., SAPS msg: Application Ref. 10470664 make TIKKA calibre 6MM MUSGRAVE s/n OB14468',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: HunterUi.cardColor(ThemeController.instance),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.sms_outlined),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _parseSmsMessage,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text(
                  'Extract Details from SMS',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
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
        // Firearm Make Input (parsed from SMS or manual)
        TextField(
          controller: _makeController,
          decoration: InputDecoration(
            labelText: 'Firearm Make / Brand',
            hintText: 'Parsed from SMS if available, e.g., TIKKA T3X',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            prefixIcon: const Icon(Icons.precision_manufacturing_outlined),
          ),
        ),
        const SizedBox(height: 12),
        // Calibre Input (parsed from SMS or manual)
        TextField(
          controller: _calibreController,
          decoration: InputDecoration(
            labelText: 'Calibre',
            hintText: 'Parsed from SMS, e.g., 6MM MUSGRAVE',
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
            prefixIcon: const Icon(Icons.category_outlined),
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
              setState(() => _selectedApplicationType = value);
            }
          },
        ),
        const SizedBox(height: 16),
        // Register Button
        ElevatedButton(
          onPressed: _isLoading ? null : _registerApplication,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
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
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
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
        child: ListView.builder(
          padding: EdgeInsets.only(bottom: SafeBottomInset.of(context)),
          itemCount: 2,
          itemBuilder: (context, index) {
            // Item 0 is always the register accordion + tracked header so the
            // whole page scrolls as ONE unit -- no hidden double scroll, no
            // wasted vertical space, and no content clipped by a nested
            // Expanded on small screens / large text scales.
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Register New Application — collapsible accordion
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _buildRegisterAccordion(theme, hunterTheme),
                  ),
                  // Live CFR status enquiry (reference + serial).
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildEnquiryPanel(theme, hunterTheme),
                  ),
                  // Active Tracker header + manual refresh button
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
                        IconButton(
                          tooltip: 'Refresh all statuses',
                          onPressed: _isRefreshingAll ? null : _manualRefresh,
                          icon: _isRefreshingAll
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.refresh,
                                  color: theme.colorScheme.primary,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            }

            // Item 1 is the tracked-applications section (auth-gated).
            if (_currentUserId == null) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Please log in to view tracked applications',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.hintColor),
                ),
              );
            }

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('license_applications')
                  .where('hunterId', isEqualTo: _currentUserId)
                  .orderBy('lastChecked', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error loading applications: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
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

                return Column(
                  children: [
                    for (final doc in docs)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SapsApplicationCard(
                          application: SapsApplication.fromFirestore(
                            doc as DocumentSnapshot<Map<String, dynamic>>,
                          ),
                          trackerService: _trackerService,
                        ),
                      ),
                  ],
                );
              },
            );
          },
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
              // Header row. The application type is Expanded and the status
              // badge is Flexible so a long status string (e.g. the real CFR
              // phrase "Application received at DFO") can never overflow the
              // card width at large text scales -- the badge shrinks and
              // ellipsizes instead of pushing a yellow RenderFlex stripe.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      application.applicationType,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        application.currentStatus,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Prominent submission date milestone. Falls back to the record's
              // creation timestamp (createdAt) when the official submittedAt is
              // missing / unrecorded so the tally + this row always render.
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
                      _submissionDateLabel(),
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
                  if (application.firearmMake.trim().isNotEmpty)
                    HunterDataPill(
                      theme: hunterTheme,
                      pill: HunterMediaPill(
                        icon: Icons.precision_manufacturing_outlined,
                        label: application.firearmMake.trim(),
                        amber: true,
                      ),
                    ),
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
              // Next anticipated status indicator.
              Row(
                children: [
                  Icon(
                    Icons.arrow_forward,
                    size: 15,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Next: ${application.nextStatusLabel}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Current status stage description.
              Text(
                application.currentStatusDescription,
                style: TextStyle(fontSize: 12, color: theme.hintColor),
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
    // The firearm details section renders immediately (from the card's model)
    // while the tracking details are still loading / unavailable, so the
    // make / calibre / serial pills appear as soon as the card is expanded.
    final firearmSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, 'FIREARM DETAILS'),
        const SizedBox(height: 8),
        _detailRow(
          theme,
          Icons.gps_fixed,
          application.firearmLabel,
          null,
        ),
        if (application.firearmMake.trim().isNotEmpty ||
            application.calibre.isNotEmpty ||
            application.serialNumber.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (application.firearmMake.trim().isNotEmpty)
                  _expandedPill(
                    theme,
                    Icons.precision_manufacturing_outlined,
                    application.firearmMake.trim(),
                  ),
                if (application.calibre.isNotEmpty)
                  _expandedPill(theme, Icons.gps_fixed, application.calibre),
                if (application.serialNumber.isNotEmpty)
                  _expandedPill(
                    theme,
                    Icons.pin_outlined,
                    's/n ${application.serialNumber}',
                  ),
              ],
            ),
          ),
      ],
    );

    if (!_detailsLoaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 24),
          firearmSection,
          const SizedBox(height: 16),
          const Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      );
    }

    final details = _details;
    if (details == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 24),
          firearmSection,
          const SizedBox(height: 16),
          Text(
            'Tracking details are not available for this application.',
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        firearmSection,
        const SizedBox(height: 16),
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

  /// Compact themed pill used inside the expanded details view (e.g. the
  /// firearm make / calibre / serial chips under the FIREARM DETAILS section).
  Widget _expandedPill(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
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

  /// Labels the prominent submission-date row: prefers the official
  /// [SapsApplication.submittedAt], falling back to the record's creation
  /// timestamp ([SapsApplication.createdAt]) when the official date is
  /// missing / unrecorded. Renders a muted "not recorded" only when the
  /// record has neither timestamp.
  String _submissionDateLabel() {
    final effective = application.effectiveSubmissionDate;
    if (effective != null) {
      final fromFallback = application.submittedAt == null;
      final suffix = fromFallback ? ' (record created)' : '';
      return 'Submitted: ${_formatDateOnly(effective)}$suffix';
    }
    return 'Submitted: not recorded';
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
