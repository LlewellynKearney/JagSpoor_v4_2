import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/admin/models/admin_user_metrics.dart';

/// Unit tests for the Task 6 model additions: the role category (Hunter /
/// Outfitter / Dual / No Role), the dashboard audience counts, the per-day
/// new-user series and the date / trial display helpers.
void main() {
  AdminUserRecord rec({
    String uid = 'u',
    String role = '',
    bool dual = false,
    List<String> roles = const [],
    DateTime? createdAt,
    String status = '',
    DateTime? trialEnd,
    DateTime? trialStart,
    DateTime? premiumExpiry,
    bool hasActivePurchase = false,
  }) =>
      AdminUserRecord(
        uid: uid,
        role: role,
        isDualRole: dual,
        roles: roles,
        createdAt: createdAt,
        subscriptionStatus: status,
        trialEnd: trialEnd,
        trialStart: trialStart,
        premiumExpiry: premiumExpiry,
        hasActivePurchase: hasActivePurchase,
      );

  group('AdminUserRoleCategory / roleCategory', () {
    test('hunter role maps to hunter', () {
      expect(rec(role: 'hunter').roleCategory, AdminUserRoleCategory.hunter);
    });

    test('outfitter role maps to outfitter', () {
      expect(rec(role: 'outfitter').roleCategory,
          AdminUserRoleCategory.outfitter);
    });

    test('dual role maps to dual (role: dual shorthand)', () {
      expect(rec(role: 'dual').roleCategory, AdminUserRoleCategory.dual);
    });

    test('isDualRole flag maps to dual', () {
      expect(rec(dual: true).roleCategory, AdminUserRoleCategory.dual);
    });

    test('roles array with both hunter + outfitter maps to dual', () {
      expect(
        rec(roles: ['hunter', 'outfitter']).roleCategory,
        AdminUserRoleCategory.dual,
      );
    });

    test('empty / unassigned / admin role maps to noRole', () {
      expect(rec(role: '').roleCategory, AdminUserRoleCategory.noRole);
      expect(rec(role: 'unassigned').roleCategory,
          AdminUserRoleCategory.noRole);
      expect(rec(role: 'admin').roleCategory, AdminUserRoleCategory.noRole);
    });

    test('hasNoOperationalRole excludes dual / hunter / outfitter', () {
      expect(rec(role: 'hunter').hasNoOperationalRole, isFalse);
      expect(rec(role: 'outfitter').hasNoOperationalRole, isFalse);
      expect(rec(dual: true).hasNoOperationalRole, isFalse);
      expect(rec(role: '').hasNoOperationalRole, isTrue);
    });
  });

  group('AdminUserRecord.fromMap dual detection', () {
    test('reads isDualRole flag', () {
      final r = AdminUserRecord.fromMap('u', {
        'role': 'hunter',
        'isDualRole': true,
      });
      expect(r.isDualRole, isTrue);
      expect(r.roleCategory, AdminUserRoleCategory.dual);
    });

    test('reads a roles array holding both roles', () {
      final r = AdminUserRecord.fromMap('u', {
        'role': 'hunter',
        'roles': ['hunter', 'outfitter'],
      });
      expect(r.isDualRole, isTrue);
    });

    test('a single-role roles array is NOT dual', () {
      final r = AdminUserRecord.fromMap('u', {
        'role': 'hunter',
        'roles': ['hunter'],
      });
      expect(r.isDualRole, isFalse);
      expect(r.roleCategory, AdminUserRoleCategory.hunter);
    });

    test('reads the dual shorthand', () {
      final r = AdminUserRecord.fromMap('u', {'role': 'dual'});
      expect(r.isDualRole, isTrue);
    });
  });

  group('AdminUserMetrics audience counts', () {
    test('totalUsers counts each account once even when dual', () {
      final m = AdminUserMetrics.aggregate([
        rec(uid: 'h', role: 'hunter'),
        rec(uid: 'o', role: 'outfitter'),
        rec(uid: 'd', dual: true),
        rec(uid: 'n', role: ''),
      ], filter: AdminDateFilter.allTime);
      expect(m.totalUsers, 4);
      // Dual counts on both sides.
      expect(m.hunterCount, 2);
      expect(m.outfitterCount, 2);
      expect(m.noRoleCount, 1);
    });

    test('noRoleCount excludes admins/hunters/outfitters/dual', () {
      final m = AdminUserMetrics.aggregate([
        rec(uid: 'a', role: 'admin'),
        rec(uid: 'u', role: 'unassigned'),
        rec(uid: 'h', role: 'hunter'),
      ], filter: AdminDateFilter.allTime);
      expect(m.noRoleCount, 2);
    });

    test('empty set is all zeros', () {
      final m = AdminUserMetrics.aggregate(const [],
          filter: AdminDateFilter.allTime);
      expect(m.totalUsers, 0);
      expect(m.hunterCount, 0);
      expect(m.outfitterCount, 0);
      expect(m.noRoleCount, 0);
    });
  });

  group('adminNewUsersByDay', () {
    test('builds a 7-day window with zero-filled days', () {
      final now = DateTime(2026, 5, 10, 12);
      final series = adminNewUsersByDay([
        rec(uid: 'a', createdAt: DateTime(2026, 5, 10, 9)),
        rec(uid: 'b', createdAt: DateTime(2026, 5, 10, 18)),
        rec(uid: 'c', createdAt: DateTime(2026, 5, 8)),
        // Outside the window.
        rec(uid: 'd', createdAt: DateTime(2026, 4, 1)),
      ], days: 7, now: now);

      expect(series.length, 7);
      // Oldest → newest.
      expect(series.first.key, DateTime(2026, 5, 4));
      expect(series.last.key, DateTime(2026, 5, 10));
      expect(series.last.value, 2); // two on the last day
      final may8 = series.firstWhere((e) => e.key == DateTime(2026, 5, 8));
      expect(may8.value, 1);
      // An empty day is present with zero.
      final may5 = series.firstWhere((e) => e.key == DateTime(2026, 5, 5));
      expect(may5.value, 0);
    });

    test('accounts with no createdAt are ignored', () {
      final now = DateTime(2026, 5, 10);
      final series = adminNewUsersByDay([
        rec(uid: 'x'),
      ], days: 7, now: now);
      expect(series.fold<int>(0, (a, e) => a + e.value), 0);
    });
  });

  group('formatAdminDate', () {
    test('formats as yyyy-MM-dd with zero padding', () {
      expect(formatAdminDate(DateTime(2026, 1, 2)), '2026-01-02');
      expect(formatAdminDate(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('null renders an em dash', () {
      expect(formatAdminDate(null), '—');
    });
  });

  group('AdminUserRecord.trialLabel', () {
    final now = DateTime(2026, 6, 1);

    test('Converted for an active subscriber', () {
      final r = rec(
        status: 'active',
        premiumExpiry: now.add(const Duration(days: 10)),
      );
      expect(r.trialLabel(now), 'Converted');
    });

    test('Active for a running trial', () {
      final r = rec(
        status: 'trialing',
        trialEnd: now.add(const Duration(days: 5)),
      );
      expect(r.trialLabel(now), 'Active');
    });

    test('Expired for a past trial end with no subscription', () {
      final r = rec(
        status: 'trialing',
        trialEnd: now.subtract(const Duration(days: 1)),
      );
      expect(r.trialLabel(now), 'Expired');
    });

    test('None when there was never a trial', () {
      final r = rec(createdAt: now.subtract(const Duration(days: 90)));
      expect(r.trialLabel(now), 'None');
    });
  });

  group('Timestamp tolerance', () {
    test('fromMap parses a Timestamp createdAt', () {
      final r = AdminUserRecord.fromMap('u', {
        'createdAt': Timestamp.fromDate(DateTime(2026, 7, 8)),
      });
      expect(r.createdAt, isNotNull);
      expect(formatAdminDate(r.createdAt), '2026-07-08');
    });

    test('a fully empty document parses without throwing', () {
      final r = AdminUserRecord.fromMap('u', null);
      expect(r.roleCategory, AdminUserRoleCategory.noRole);
      expect(r.trialLabel(DateTime.now()), 'None');
    });
  });
}
