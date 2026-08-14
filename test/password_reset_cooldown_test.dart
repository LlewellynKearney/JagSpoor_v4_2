import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/auth/services/password_reset_cooldown.dart';

void main() {
  group('PasswordResetCooldown', () {
    test('default cooldown window is 60 seconds', () {
      expect(PasswordResetCooldown.defaultCooldownSeconds, 60);
    });

    group('expiry', () {
      test('expiry is from + seconds', () {
        final from = DateTime(2026, 8, 14, 12, 0, 0);
        final until = PasswordResetCooldown.expiry(from: from);
        expect(until, from.add(const Duration(seconds: 60)));
      });

      test('custom seconds window honoured', () {
        final from = DateTime(2026, 8, 14, 12, 0, 0);
        final until = PasswordResetCooldown.expiry(
          from: from,
          seconds: 30,
        );
        expect(until, from.add(const Duration(seconds: 30)));
      });
    });

    group('remainingSeconds', () {
      test('full window at the start', () {
        final from = DateTime(2026, 8, 14, 12, 0, 0);
        final until = PasswordResetCooldown.expiry(from: from);
        expect(
          PasswordResetCooldown.remainingSeconds(now: from, until: until),
          60,
        );
      });

      test('partial elapsed', () {
        final from = DateTime(2026, 8, 14, 12, 0, 0);
        final until = PasswordResetCooldown.expiry(from: from);
        final now = from.add(const Duration(seconds: 45));
        expect(
          PasswordResetCooldown.remainingSeconds(now: now, until: until),
          15,
        );
      });

      test('floored at 0 when expired', () {
        final from = DateTime(2026, 8, 14, 12, 0, 0);
        final until = PasswordResetCooldown.expiry(from: from);
        final now = from.add(const Duration(seconds: 120));
        expect(
          PasswordResetCooldown.remainingSeconds(now: now, until: until),
          0,
        );
      });

      test('exactly 0 at the expiry instant', () {
        final from = DateTime(2026, 8, 14, 12, 0, 0);
        final until = PasswordResetCooldown.expiry(from: from);
        expect(
          PasswordResetCooldown.remainingSeconds(now: until, until: until),
          0,
        );
      });
    });

    group('isActive', () {
      test('true before the expiry', () {
        final from = DateTime(2026, 8, 14, 12, 0, 0);
        final until = PasswordResetCooldown.expiry(from: from);
        expect(
          PasswordResetCooldown.isActive(
            now: from.add(const Duration(seconds: 1)),
            until: until,
          ),
          isTrue,
        );
      });

      test('false at the expiry instant', () {
        final from = DateTime(2026, 8, 14, 12, 0, 0);
        final until = PasswordResetCooldown.expiry(from: from);
        expect(
          PasswordResetCooldown.isActive(now: until, until: until),
          isFalse,
        );
      });

      test('false after the expiry', () {
        final from = DateTime(2026, 8, 14, 12, 0, 0);
        final until = PasswordResetCooldown.expiry(from: from);
        expect(
          PasswordResetCooldown.isActive(
            now: from.add(const Duration(seconds: 61)),
            until: until,
          ),
          isFalse,
        );
      });
    });
  });
}
