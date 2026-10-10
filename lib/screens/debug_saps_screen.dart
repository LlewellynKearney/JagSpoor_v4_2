import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/hunter_mode/services/saps_cfr_scraper_client.dart';
import '../features/hunter_mode/services/saps_status_classifier.dart'
    show kSapsStageNeedSerialAndRef;

/// DEBUG-ONLY screen that performs the real SAPS CFR enquiry against the
/// official portal (`saps.gov.za`) directly from the device.
///
/// It exists purely for developer verification of the live portal response
/// (form field names, the csrf handshake, the results table, the
/// "data were updated on <b>DATE</b>" notice and the NOT_FOUND wording).
/// Enter a reference + serial number, tap ENQUIRE, and the screen prints the
/// RAW status phrase, the classified STAGE index, the display LABEL and the
/// portal UPDATED date.
///
/// Only reachable from a `kDebugMode` build via the `/debug_saps` route.
class DebugSapsScreen extends StatefulWidget {
  const DebugSapsScreen({super.key});

  @override
  State<DebugSapsScreen> createState() => _DebugSapsScreenState();
}

class _DebugSapsScreenState extends State<DebugSapsScreen> {
  final _refController = TextEditingController(text: '10470664');
  final _serialController = TextEditingController(text: 'OB14468');

  bool _running = false;
  String? _error;
  SapsCfrStatus? _result;

  @override
  void dispose() {
    _refController.dispose();
    _serialController.dispose();
    super.dispose();
  }

  Future<void> _enquire() async {
    final ref = _refController.text.trim();
    final serial = _serialController.text.trim();
    if (ref.isEmpty) {
      setState(() {
        _error = 'Reference number is required.';
        _result = null;
      });
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });

    try {
      // No webhook configured -> in a debug build the client uses the direct
      // device -> portal path.
      final client = SapsCfrScraperClient();
      final result = await client.fetchStatus(
        referenceNumber: ref,
        idNumber: '',
        serialNumber: serial,
      );
      if (!mounted) return;
      // Log the portal HTML shape (first 500 chars) so the live response is
      // visible in the console even when the parse yields nothing.
      if (result != null && result.htmlSnippet.isNotEmpty) {
        debugPrint(
          'DebugSapsScreen: portal htmlSnippet '
          '(${result.htmlSnippet.length} chars): ${result.htmlSnippet}',
        );
      }
      setState(() {
        _running = false;
        _result = result;
        _error = result == null
            ? 'No response parsed. Check connectivity / the portal HTML shape.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = 'Enquiry failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SAPS Debug Tracker'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'DEBUG ONLY — queries saps.gov.za directly. Not available '
                    'in release builds.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _refController,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Reference Number (fsref)',
              hintText: 'e.g. 10470664',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _serialController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Serial Number (fserial)',
              hintText: 'e.g. OB14468',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.pin_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'For firearm renewal: enter BOTH Ref + Serial. '
                  'For competency: Ref only.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running ? null : _enquire,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_running ? 'ENQUIRING…' : 'ENQUIRE (LIVE)'),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
              ),
              child: Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
              ),
            ),
          if (result != null) _buildResult(theme, result),
        ],
      ),
    );
  }

  Widget _buildResult(ThemeData theme, SapsCfrStatus result) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RESULT', style: theme.textTheme.titleMedium),
            const Divider(height: 20),
            _row('RAW', result.rawStatus),
            _row('STAGE', result.stage.toString()),
            _row('LABEL', result.displayLabel),
            _row(
              'UPDATED',
              result.sapsUpdatedAt?.toIso8601String() ?? '—',
            ),
            _row('NOT FOUND', result.notFound ? 'true' : 'false'),
            if (result.stage == kSapsStageNeedSerialAndRef) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                ),
                child: Text(
                  'NEED_SERIAL_AND_REF — the portal requires BOTH a serial '
                  'number AND a reference number for firearm applications. '
                  'For a competency certificate, submit the reference alone.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
            if (result.applicationType.isNotEmpty)
              _row('TYPE', result.applicationType),
            if (result.applicationNumber.isNotEmpty)
              _row('APP NO', result.applicationNumber),
            if (result.calibre.isNotEmpty) _row('CALIBRE', result.calibre),
            if (result.make.isNotEmpty) _row('MAKE', result.make),
            if (result.serialNumber.isNotEmpty)
              _row('SERIAL', result.serialNumber),
            if (result.statusDate.isNotEmpty)
              _row('STATUS DATE', result.statusDate),
            if (result.statusDescription.isNotEmpty)
              _row('DESCRIPTION', result.statusDescription),
            if (result.nextStep.isNotEmpty) _row('NEXT STEP', result.nextStep),
            if (kDebugMode && result.raw != null) ...[
              const SizedBox(height: 12),
              Text('RAW PAYLOAD', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                result.raw.toString(),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (kDebugMode && result.htmlSnippet.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'PORTAL HTML SNIPPET (first 500 chars)',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              SelectableText(
                result.htmlSnippet,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
