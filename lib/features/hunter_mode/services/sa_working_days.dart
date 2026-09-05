/// South African working-day arithmetic used by the SAPS tracker's milestone
/// tallies.
///
/// A "working day" is any day that is neither a weekend (Saturday / Sunday)
/// nor a South African public holiday. Public holidays that fall on a Sunday
/// are observed on the following Monday (the Public Holidays Act), so the
/// shifted Monday is excluded as well.
class SaWorkingDays {
  SaWorkingDays._();

  /// Returns `true` when [date] is a South African public holiday (including
  /// the Monday-shift for holidays that fall on a Sunday).
  static bool isPublicHoliday(DateTime date) {
    final y = date.year;
    final m = date.month;
    final d = date.day;

    // Fixed-date public holidays.
    const fixed = <(int, int)>{
      (1, 1), // New Year's Day
      (3, 21), // Human Rights Day
      (4, 27), // Freedom Day
      (5, 1), // Workers' Day
      (6, 16), // Youth Day
      (8, 9), // National Women's Day
      (9, 24), // Heritage Day
      (12, 16), // Day of Reconciliation
      (12, 25), // Christmas Day
      (12, 26), // Day of Goodwill
    };
    if (fixed.contains((m, d))) return true;

    // Easter-based holidays (Good Friday + Family Day / Easter Monday).
    final easter = _easterSunday(y);
    final goodFriday = easter.subtract(const Duration(days: 2));
    final familyDay = easter.add(const Duration(days: 1));
    if (date.year == y &&
        date.month == goodFriday.month &&
        date.day == goodFriday.day) {
      return true;
    }
    if (date.year == y &&
        date.month == familyDay.month &&
        date.day == familyDay.day) {
      return true;
    }

    // Sunday-shift: a public holiday falling on a Sunday is observed on the
    // following Monday.
    final sundayHolidays = <DateTime>[
      DateTime(y, 1, 1),
      DateTime(y, 3, 21),
      DateTime(y, 4, 27),
      DateTime(y, 5, 1),
      DateTime(y, 6, 16),
      DateTime(y, 8, 9),
      DateTime(y, 9, 24),
      DateTime(y, 12, 16),
      DateTime(y, 12, 25),
      DateTime(y, 12, 26),
      goodFriday,
      familyDay,
    ];
    for (final holiday in sundayHolidays) {
      if (holiday.weekday == DateTime.sunday) {
        final observed = holiday.add(const Duration(days: 1));
        if (date.year == observed.year &&
            date.month == observed.month &&
            date.day == observed.day) {
          return true;
        }
      }
    }

    return false;
  }

  /// Returns `true` when [date] is a working day (not a weekend and not a
  /// South African public holiday).
  static bool isWorkingDay(DateTime date) {
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return false;
    }
    return !isPublicHoliday(date);
  }

  /// Counts the number of working days in the half-open interval
  /// `[start, end)` -- i.e. from [start] (inclusive) up to but NOT including
  /// [end]. Both dates are normalised to their date component (midnight
  /// local) before counting, so a time component on either end never skews
  /// the tally.
  ///
  /// Returns `null` when [end] is on or before [start] (the milestone has
  /// not yet elapsed), which the UI renders as an in-progress dash.
  static int? workingDaysBetween(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    if (!e.isAfter(s)) return null;

    var count = 0;
    var cursor = s;
    while (cursor.isBefore(e)) {
      if (isWorkingDay(cursor)) count++;
      cursor = cursor.add(const Duration(days: 1));
    }
    return count;
  }

  /// Convenience: working days elapsed from [start] up to (and including)
  /// [now]'s date. Returns `null` when [start] is null or in the future.
  static int? workingDaysSince(DateTime? start, DateTime now) {
    if (start == null) return null;
    final s = DateTime(start.year, start.month, start.day);
    final n = DateTime(now.year, now.month, now.day);
    if (n.isBefore(s)) return null;
    // +1 so the submission day itself counts as the first working day.
    final inclusive = workingDaysBetween(s, n.add(const Duration(days: 1)));
    return inclusive;
  }

  /// Computes the Gregorian date of Easter Sunday for [year] using the
  /// Anonymous Gregorian algorithm (valid for 1900-2099).
  static DateTime _easterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }
}
