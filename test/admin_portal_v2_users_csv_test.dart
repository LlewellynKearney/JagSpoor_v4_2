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
    DateTime? premiumExpiry,
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
        premiumExpiry: premiumExpiry,
        trialEnd: trialEnd,
      );

  group('header + column order', () {
    test('the header row is exactly the brief columns in order', () {
      expect(AdminUsersCsv.headers, const [
        'Email',
        'First Name',
        'Surname',
        'Role',
        'Created Date',
        'Last Active',
        'Subscription Status',
        'Subscription Provider',
      ]);
    });

    test('build() emits the header as the first line', () {
      final csv = AdminUsersCsv.build(const <AdminUserRecord>[]);
      expect(csv, 'Email,First Name,Surname,Role,Created Date,Last Active,'
          'Subscription Status,Subscription Provider\r\n');
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
          lastActive: DateTime(2026, 11, 1),
          subscriptionStatus: 'active',
          provider: 'google_play',
          premiumExpiry: now.add(const Duration(days: 20)),
        ),
      ], now: now);

      final lines = csv.trim().split('\r\n');
      expect(lines, hasLength(2));
      expect(
        lines[1],
        'hunter@example.com,Jan,Bosch,hunter,2026-03-04,2026-11-01,Active,Google',
      );
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
      // Every data cell is blank (7 commas between 8 empty cells).
      expect(lines[1], ',,,,,,,');
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

  group('subscription cells', () {
    final now = DateTime(2026, 11, 15);

    test('Active when premium with a future expiry', () {
      final r = rec(
        uid: 'u',
        subscriptionStatus: 'active',
        premiumExpiry: now.add(const Duration(days: 10)),
      );
      expect(AdminUsersCsv.subscriptionStatusCell(r, now), 'Active');
    });

    test('Trial when the trial end is in the future', () {
      final r = rec(uid: 'u', trialEnd: now.add(const Duration(days: 5)));
      expect(AdminUsersCsv.subscriptionStatusCell(r, now), 'Trial');
    });

    test('Cancelled when the document records a cancellation', () {
      final r = rec(uid: 'u', subscriptionStatus: 'cancelled');
      expect(AdminUsersCsv.subscriptionStatusCell(r, now), 'Cancelled');
    });

    test('Expired when a premium expiry has passed', () {
      final r = rec(
        uid: 'u',
        subscriptionStatus: 'active',
        premiumExpiry: now.subtract(const Duration(days: 1)),
      );
      expect(AdminUsersCsv.subscriptionStatusCell(r, now), 'Expired');
    });

    test('blank when the account never had a subscription', () {
      expect(AdminUsersCsv.subscriptionStatusCell(rec(uid: 'u'), now), '');
    });

    test('provider cell maps Google Play + PayFast, blank otherwise', () {
      expect(AdminUsersCsv.subscriptionProviderCell(rec(uid: 'u', provider: 'google_play')), 'Google');
      expect(AdminUsersCsv.subscriptionProviderCell(rec(uid: 'u', provider: 'payfast')), 'PayFast');
      expect(AdminUsersCsv.subscriptionProviderCell(rec(uid: 'u', provider: 'payfast_alternative')), 'PayFast');
      expect(AdminUsersCsv.subscriptionProviderCell(rec(uid: 'u')), '');
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
