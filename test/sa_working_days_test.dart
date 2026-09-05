import 'package:flutter_test/flutter_test.dart';

import 'package:jagspoor/features/hunter_mode/services/sa_working_days.dart';

void main() {
  group('SaWorkingDays.isWorkingDay', () {
    test('Monday is a working day', () {
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 9, 7)), isTrue);
    });

    test('Saturday and Sunday are not working days', () {
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 9, 5)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 9, 6)), isFalse);
    });

    test('fixed public holidays are not working days', () {
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 1, 1)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 3, 21)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 4, 27)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 5, 1)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 6, 16)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 8, 9)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 9, 24)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 12, 16)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 12, 25)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 12, 26)), isFalse);
    });

    test('2 January is a normal working day when it is not a shift', () {
      // 2 Jan 2026 is a Friday and no holiday falls on it -> working day.
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 1, 2)), isTrue);
    });

    test('Easter-based holidays are not working days (2026: 3-6 Apr)', () {
      // Good Friday 2026 = 3 Apr, Family Day = 6 Apr.
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 4, 3)), isFalse);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 4, 6)), isFalse);
      // The surrounding working days are not holidays.
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 4, 2)), isTrue);
      expect(SaWorkingDays.isWorkingDay(DateTime(2026, 4, 7)), isTrue);
    });

    test('a Sunday holiday is observed on the following Monday', () {
      // 1 Jan 2026 is a Thursday; 1 Jan 2023 was a Sunday -> observed Mon 2 Jan.
      // 2023: New Year's Day (Sun 1 Jan) observed Mon 2 Jan 2023.
      expect(SaWorkingDays.isWorkingDay(DateTime(2023, 1, 2)), isFalse);
      // 2022: 1 Jan was a Saturday -> no shift; Mon 3 Jan is a working day.
      expect(SaWorkingDays.isWorkingDay(DateTime(2022, 1, 3)), isTrue);
    });
  });

  group('SaWorkingDays.workingDaysBetween', () {
    test('counts weekdays across a simple week', () {
      // Mon 7 Sep -> Mon 14 Sep 2026 = 5 working days (Mon-Fri).
      expect(
        SaWorkingDays.workingDaysBetween(
          DateTime(2026, 9, 7),
          DateTime(2026, 9, 14),
        ),
        5,
      );
    });

    test('returns null when end is on or before start', () {
      expect(
        SaWorkingDays.workingDaysBetween(
          DateTime(2026, 9, 7),
          DateTime(2026, 9, 7),
        ),
        isNull,
      );
      expect(
        SaWorkingDays.workingDaysBetween(
          DateTime(2026, 9, 14),
          DateTime(2026, 9, 7),
        ),
        isNull,
      );
    });

    test('ignores the time component on both ends', () {
      // Same date range but with arbitrary times -> identical count.
      expect(
        SaWorkingDays.workingDaysBetween(
          DateTime(2026, 9, 7, 23, 59),
          DateTime(2026, 9, 14, 0, 1),
        ),
        5,
      );
    });

    test('excludes a public holiday inside the range', () {
      // Fri 25 Sep -> Fri 2 Oct 2026. Heritage Day is Thu 24 Sep (outside).
      // Use a range that spans Heritage Day: Wed 23 Sep -> Wed 30 Sep.
      // Working days: 23 (Wed), 24 (Thu, HOLIDAY), 25 (Fri), 28 (Mon),
      // 29 (Tue) => 4 (30 is the exclusive end).
      expect(
        SaWorkingDays.workingDaysBetween(
          DateTime(2026, 9, 23),
          DateTime(2026, 9, 30),
        ),
        4,
      );
    });
  });

  group('SaWorkingDays.workingDaysSince', () {
    test('counts the submission day as the first working day', () {
      // Submitted Mon 7 Sep 2026, now Mon 7 Sep 2026 -> 1.
      expect(
        SaWorkingDays.workingDaysSince(
            DateTime(2026, 9, 7), DateTime(2026, 9, 7)),
        1,
      );
      // Submitted Mon 7 Sep, now Fri 11 Sep -> 5 working days.
      expect(
        SaWorkingDays.workingDaysSince(
            DateTime(2026, 9, 7), DateTime(2026, 9, 11)),
        5,
      );
    });

    test('returns null for a null or future start', () {
      expect(
          SaWorkingDays.workingDaysSince(null, DateTime(2026, 9, 7)), isNull);
      expect(
        SaWorkingDays.workingDaysSince(
            DateTime(2026, 9, 14), DateTime(2026, 9, 7)),
        isNull,
      );
    });

    test('excludes weekends and holidays from the tally', () {
      // Submitted Wed 23 Sep 2026, now Wed 30 Sep 2026.
      // Working days incl. submission day: 23 (Wed), 25 (Fri), 28 (Mon),
      // 29 (Tue), 30 (Wed) = 5 (24 Sep Heritage Day + weekend excluded).
      expect(
        SaWorkingDays.workingDaysSince(
          DateTime(2026, 9, 23),
          DateTime(2026, 9, 30),
        ),
        5,
      );
    });
  });
}
