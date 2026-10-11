import 'package:flutter/material.dart';

import '../../../widgets/jagspoor_review_modal.dart';
import 'review_service.dart';

/// Bridges [ReviewService.shouldPrompt] to the [JagspoorReviewModal].
///
/// The dashboards call [maybeShow] after a trophy is saved or a booking is
/// confirmed. The prompt fires at most ONCE per app session (the one-shot
/// guard) and only when the `admin_config/review_config` gate allows it
/// (enabled + minimum launches + cooldown elapsed).
class ReviewPromptCoordinator {
  ReviewPromptCoordinator._();

  /// One-shot per-session guard so the modal can never appear twice in a row
  /// even if several prompt-worthy events fire in the same session.
  static bool _shownThisSession = false;

  @visibleForTesting
  static void resetSession() {
    _shownThisSession = false;
  }

  /// Evaluates the review gate and, when eligible, marks the prompt (starts
  /// the cooldown + logs the `feature_usage_events` row) and shows the modal.
  ///
  /// [isOutfitter] selects the mode-specific prompt title + WhatsApp copy.
  ///
  /// Returns `true` when the modal was shown. Fully failure-tolerant: any
  /// error resolves to `false` so a prompt can never break a user flow.
  static Future<bool> maybeShow(
    BuildContext context, {
    bool isOutfitter = false,
  }) async {
    if (_shownThisSession) return false;
    try {
      final service = ReviewService.instance;
      if (!await service.shouldPrompt()) return false;
      final config = await service.loadConfig();
      if (!context.mounted) return false;
      await service.markPrompted();
      _shownThisSession = true;
      if (!context.mounted) return true;
      await JagspoorReviewModal.show(
        context,
        config: config,
        isOutfitter: isOutfitter,
      );
      return true;
    } catch (e) {
      debugPrint('ReviewPromptCoordinator.maybeShow: $e');
      return false;
    }
  }
}
