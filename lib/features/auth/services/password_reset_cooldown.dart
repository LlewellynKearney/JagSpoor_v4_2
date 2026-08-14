/// Pure helper for the password-reset retry cooldown used by the
/// "Forgot Password?" dialog.
///
/// The cooldown prevents a user from spamming duplicate reset tokens (each
/// Firebase reset email invalidates the previous link and queues another
/// delivery, which is the root cause of the perceived "email delay"). After a
/// successful send (or a Firebase `too-many-requests` rejection) the dialog
/// enters a [defaultCooldownSeconds]-second cooldown during which the send
/// button is disabled and a live countdown is shown.
///
/// The arithmetic is split into pure functions so it is fully unit-testable
/// with no Flutter / widget dependencies. The owning dialog widget supplies
/// `DateTime.now()` (real clock in production) and a `Timer.periodic` for the
/// 1-second tick.
class PasswordResetCooldown {
  PasswordResetCooldown._();

  /// Default cooldown window after a successful reset send.
  static const int defaultCooldownSeconds = 60;

  /// Returns the absolute [DateTime] at which a cooldown starting [from] will
  /// expire, given a [seconds] window.
  static DateTime expiry({
    required DateTime from,
    int seconds = defaultCooldownSeconds,
  }) {
    return from.add(Duration(seconds: seconds));
  }

  /// Remaining seconds in the cooldown, floored at 0.
  static int remainingSeconds({required DateTime now, required DateTime until}) {
    final delta = until.difference(now).inSeconds;
    return delta < 0 ? 0 : delta;
  }

  /// Whether the cooldown is still active at [now].
  static bool isActive({required DateTime now, required DateTime until}) {
    return now.isBefore(until);
  }
}

