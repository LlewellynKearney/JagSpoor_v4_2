import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/admin/models/admin_user_metrics.dart';
import 'package:jagspoor/features/admin/models/admin_users_csv.dart';

/// Task 1 — the Admin Portal V2 Users CSV exports.
///
/// Covers the header row, the exact column order, the no-role filter, empty
/// field handling (never crashes, never a placeholder), the row-count contract
/// the buttons render, and the file names.
void main() {
  AdminUserRecord rec({
    required String uid,
    String email = '',
    String firstName = '',
    String lastName = '',
    String fullName = '',
    String role = '',
    DateTime? createdAt,
    DateTime? lastActive,
    String subscriptionStatus = '',
    String provider = '',
    String plan = '',
    DateTime? premiumExpiry,
    DateTime? trialStart,
    DateTime? trialEnd,
  }) =>
      AdminUserRecord(
        uid: uid,
        email: email,
        firstName: firstName,
        lastName: lastName,
        fullName: fullName,
        role: role,
        createdAt: createdAt,
        lastActive: lastActive,
        subscriptionStatus: subscriptionStatus,
        provider: provider,
        plan: plan,
        premiumExpiry: premiumExpiry,
        trialStart: trialStart,
        trialEnd: trialEnd,
      );

  group('header + column order', () {
    test('the header row matches the Users table columns in order', () {
      expect(AdminUsersCsv.headers, const [
        'Email',
        'Name',
        'Surname',
        'Role',
        'Trial',
        'Trial Start Date',
        'Trial End Date',
        'Plan',
        'Provider',
      ]);
    });

    test('the header contains NO Created column', () {
      expect(AdminUsersCsv.headers.contains('Created'), isFalse);
      expect(AdminUsersCsv.headers.contains('Created Date'), isFalse);
    });

    test('build() emits the header as the first line', () {
      final csv = AdminUsersCsv.build(const <AdminUserRecord>[]);
      expect(csv, 'Email,Name,Surname,Role,Trial,Trial Start Date,'
          'Trial End Date,Plan,Provider\r\n');
    });

    test('a data row carries every column in order', () {
      final now = DateTime(2026, 11, 15);
      final csv = AdminUsersCsv.build([
        rec(
          uid: 'u1',
          email: 'hunter@example.com',
          firstName: 'Jan',
          lastName: 'Bosch',
          role: 'hunter',
          createdAt: DateTime(2026, 3, 4),
          trialStart: DateTime(2026, 3, 4),
          trialEnd: DateTime(2026, 11, 20),
          plan: 'hunter_monthly',
          provider: 'payfast',
        ),
      ], now: now);

      final lines = csv.trim().split('\r\n');
      expect(lines, hasLength(2));
      expect(
        lines[1],
        'hunter@example.com,Jan,Bosch,hunter,Active,2026-03-04,2026-11-20,'
        'hunter_monthly,payfast',
      );
    });

    test('Trial reflects the computed label (Active for a live trial)', () {
      final now = DateTime(2026, 11, 15);
      final csv = AdminUsersCsv.build([
        rec(
          uid: 'u1',
          email: 'a@x.com',
          trialStart: now.subtract(const Duration(days: 3)),
          trialEnd: now.add(const Duration(days: 27)),
        ),
      ], now: now);
      final lines = csv.trim().split('\r\n');
      expect(lines[1].split(','), ['a@x.com', '', '', '', 'Active',
        '2026-11-12', '2026-12-12', '', '']);
    });

    test('Trial End in the past with no subscription -> Expired', () {
      final now = DateTime(2026, 11, 15);
      final csv = AdminUsersCsv.build([
        rec(
          uid: 'u1',
          trialStart: now.subtract(const Duration(days: 60)),
          trialEnd: now.subtract(const Duration(days: 30)),
        ),
      ], now: now);
      final lines = csv.trim().split('\r\n');
      expect(lines[1].split(',')[4], 'Expired');
    });
  });

  group('no-role filter', () {
    test('noRoleUsers returns ONLY blank / none / unassigned roles', () {
      final records = [
        rec(uid: 'a', role: 'hunter'),
        rec(uid: 'b', role: ''),
        rec(uid: 'c', role: 'none'),
        rec(uid: 'd', role: 'unassigned'),
        rec(uid: 'e', role: 'outfitter'),
        rec(uid: 'f'), // missing role entirely
        rec(uid: 'g', role: '  NONE  '), // case + whitespace tolerated
      ];
      final noRole = AdminUsersCsv.noRoleUsers(records);
      expect(noRole.map((r) => r.uid).toList(), ['b', 'c', 'd', 'f', 'g']);
    });

    test('the no-role CSV contains exactly those rows', () {
      final records = [
        rec(uid: 'a', email: 'a@x.com', role: 'hunter'),
        rec(uid: 'b', email: 'b@x.com', role: ''),
        rec(uid: 'c', email: 'c@x.com', role: 'none'),
      ];
      final noRole = AdminUsersCsv.noRoleUsers(records);
      final csv = AdminUsersCsv.build(noRole);
      final lines = csv.trim().split('\r\n');
      expect(lines, hasLength(3)); // header + 2
      expect(csv.contains('a@x.com'), isFalse);
      expect(csv.contains('b@x.com'), isTrue);
      expect(csv.contains('c@x.com'), isTrue);
    });

    test('rowCount is the number of DATA rows (header excluded)', () {
      final records = [rec(uid: 'a'), rec(uid: 'b')];
      expect(AdminUsersCsv.rowCount(records), 2);
      final csv = AdminUsersCsv.build(records);
      // header + 2 rows
      expect(csv.trim().split('\r\n'), hasLength(3));
    });
  });

  group('empty field handling', () {
    test('a completely empty record exports blank cells, never crashes', () {
      final csv = AdminUsersCsv.build([rec(uid: 'empty')]);
      final lines = csv.trim().split('\r\n');
      expect(lines, hasLength(2));
      // Every data cell is blank except Trial, which computes to `None`
      // (9 cells: 8 blank + the computed trial label).
      expect(lines[1], ',,,,None,,,,');
    });

    test('a name falls back to the legacy fullName when first/last are blank',
        () {
      final r = rec(uid: 'u', fullName: 'Legacy Hunter');
      expect(r.displayName, 'Legacy Hunter');
    });

    test('a value containing a comma / quote is CSV-escaped', () {
      final csv = AdminUsersCsv.build([
        rec(uid: 'u', email: 'a,b@x.com', firstName: 'O"Brien'),
      ]);
      expect(csv.contains('"a,b@x.com"'), isTrue);
      expect(csv.contains('"O""Brien"'), isTrue);
    });

    test('csvEscape quotes only when needed', () {
      expect(csvEscape('plain'), 'plain');
      expect(csvEscape('a,b'), '"a,b"');
      expect(csvEscape('a"b'), '"a""b"');
      expect(csvEscape('a\nb'), '"a\nb"');
    });
  });

  group('Trial cell + provider cell', () {
    final now = DateTime(2026, 11, 15);

    test('Trial cell is Active when the trial end is in the future', () {
      final r = rec(uid: 'u', trialEnd: now.add(const Duration(days: 5)));
      expect(AdminUsersCsv.rowFor(r, now)[4], 'Active');
    });

    test('Trial cell is Expired when the trial end has passed', () {
      final r = rec(uid: 'u', trialEnd: now.subtract(const Duration(days: 1)));
      expect(AdminUsersCsv.rowFor(r, now)[4], 'Expired');
    });

    test('Trial cell is Converted when premium is active', () {
      final r = rec(
        uid: 'u',
        subscriptionStatus: 'active',
        premiumExpiry: now.add(const Duration(days: 10)),
      );
      expect(AdminUsersCsv.rowFor(r, now)[4], 'Converted');
    });

    test('Trial cell is None when there is no trial', () {
      expect(AdminUsersCsv.rowFor(rec(uid: 'u'), now)[4], 'None');
    });

    test('provider cell carries the raw stored provider verbatim', () {
      expect(AdminUsersCsv.rowFor(rec(uid: 'u', provider: 'google_play'), now)[8],
          'google_play');
      expect(AdminUsersCsv.rowFor(rec(uid: 'u', provider: 'payfast'), now)[8],
          'payfast');
      expect(AdminUsersCsv.rowFor(rec(uid: 'u'), now)[8], '');
    });
  });

  group('file names', () {
    test('all-users file name carries the date', () {
      expect(
        AdminUsersCsv.allUsersFileName(DateTime(2026, 11, 5)),
        'jagspoor-users-2026-11-05.csv',
      );
    });

    test('no-role file name carries the date', () {
      expect(
        AdminUsersCsv.noRoleFileName(DateTime(2026, 11, 5)),
        'jagspoor-users-no-role-2026-11-05.csv',
      );
    });
  });

  group('fromMap reads the name + lastActive fields', () {
    test('firstName / lastName / lastActive parse', () {
      final r = AdminUserRecord.fromMap('u', {
        'email': 'x@y.com',
        'firstName': 'Sipho',
        'surname': 'Nkosi',
        'lastActiveAt': DateTime(2026, 10, 2),
      });
      expect(r.firstName, 'Sipho');
      expect(r.lastName, 'Nkosi');
      expect(r.lastActive, DateTime(2026, 10, 2));
      expect(r.displayName, 'Sipho Nkosi');
    });

    test('missing fields resolve to blanks / null', () {
      final r = AdminUserRecord.fromMap('u', const {'email': 'x@y.com'});
      expect(r.firstName, '');
      expect(r.lastName, '');
      expect(r.lastActive, isNull);
      expect(r.displayName, '');
    });
  });
}
