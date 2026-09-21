import 'package:flutter/material.dart';

import '../../services/force_update_service.dart';
import '../../services/update_service.dart';

/// Hard-block dialog shown when Firebase Remote Config raises
/// `min_required_version_code` above the installed build's `versionCode`.
///
/// Deliberately **non-dismissible**: tapping the barrier does nothing and
/// `PopScope(canPop: false)` blocks the Android back button. There is no
/// "Later" affordance — the only action hands off to the Google Play in-app
/// update flow ([UpdateService.checkForImmediateUpdate]), which Play renders
/// as its own blocking update dialog.
///
/// Extracted from the splash screen so the block contract (its non-dismissible
/// nature + the server-authored copy) is widget-testable in isolation.
class ForceUpdateDialog extends StatelessWidget {
  /// The server-authored copy shown to the user.
  final String message;

  /// Optional override for the update action. Defaults to the Play in-app
  /// update flow; injectable so widget tests can assert the hand-off without
  /// touching the Play plugin.
  final VoidCallback? onUpdatePressed;

  const ForceUpdateDialog({
    super.key,
    required this.message,
    this.onUpdatePressed,
  });

  /// Convenience constructor from a [ForceUpdateDecision].
  ForceUpdateDialog.fromDecision(
    ForceUpdateDecision decision, {
    super.key,
    this.onUpdatePressed,
  }) : message = decision.message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block the system back button / predictive-back gesture.
      canPop: false,
      child: AlertDialog(
        title: const Text('Update Required'),
        content: Text(message),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.system_update_alt_rounded),
            label: const Text('UPDATE NOW'),
            onPressed: onUpdatePressed ??
                () => UpdateService.checkForImmediateUpdate(),
          ),
        ],
      ),
    );
  }
}

/// Shows the non-dismissible force-update block.
///
/// `barrierDismissible: false` keeps a tap outside the dialog from closing it;
/// [ForceUpdateDialog] additionally blocks the back button.
Future<void> showForceUpdateDialog(
  BuildContext context, {
  required String message,
  VoidCallback? onUpdatePressed,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ForceUpdateDialog(
      message: message,
      onUpdatePressed: onUpdatePressed,
    ),
  );
}