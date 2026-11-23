import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_feature_flag.dart';

void main() {
  group('VeldCarryFeatureFlag.shouldEnable (pure gate)', () {
    test('compile-time false => OFF even when the control plane is true', () {
      expect(
        VeldCarryFeatureFlag.shouldEnable(
          compileTime: false,
          adminConfig: true,
        ),
        isFalse,
      );
    });

    test('control plane false => OFF even when compile-time is true', () {
      expect(
        VeldCarryFeatureFlag.shouldEnable(
          compileTime: true,
          adminConfig: false,
        ),
        isFalse,
      );
    });

    test('both switches true => ON', () {
      expect(
        VeldCarryFeatureFlag.shouldEnable(
          compileTime: true,
          adminConfig: true,
        ),
        isTrue,
      );
    });

    test('both switches false => OFF', () {
      expect(
        VeldCarryFeatureFlag.shouldEnable(
          compileTime: false,
          adminConfig: false,
        ),
        isFalse,
      );
    });
  });

  group('control plane fails closed', () {
    test('missing admin_config/feature_flags doc => OFF', () async {
      final flag = VeldCarryFeatureFlag.forTesting(
        compileTimeEnabled: true,
        firestore: FakeFirebaseFirestore(),
      );

      expect(await flag.refresh(), isFalse);
      expect(flag.adminConfigEnabled, isFalse);
      expect(flag.isVeldCarryEnabled, isFalse);
    });

    test('veldCarryEnabled true + compile-time true => ON', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('admin_config').doc('feature_flags').set({
        'veldCarryEnabled': true,
      });
      final flag = VeldCarryFeatureFlag.forTesting(
        compileTimeEnabled: true,
        firestore: firestore,
      );

      expect(await flag.refresh(), isTrue);
      expect(flag.adminConfigEnabled, isTrue);
      expect(flag.isVeldCarryEnabled, isTrue);
    });

    test('control plane true but compile-time false => OFF', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('admin_config').doc('feature_flags').set({
        'veldCarryEnabled': true,
      });
      final flag = VeldCarryFeatureFlag.forTesting(firestore: firestore);

      // The read succeeds, but the compile-time switch is off.
      expect(await flag.refresh(), isTrue);
      expect(flag.isVeldCarryEnabled, isFalse);
    });

    test('doc present without the field => OFF', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('admin_config').doc('feature_flags').set({
        'someOtherFlag': true,
      });
      final flag = VeldCarryFeatureFlag.forTesting(
        compileTimeEnabled: true,
        firestore: firestore,
      );

      expect(await flag.refresh(), isFalse);
      expect(flag.isVeldCarryEnabled, isFalse);
    });

    test('non-boolean value fails closed', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('admin_config').doc('feature_flags').set({
        'veldCarryEnabled': 'true',
      });
      final flag = VeldCarryFeatureFlag.forTesting(
        compileTimeEnabled: true,
        firestore: firestore,
      );

      expect(await flag.refresh(), isFalse);
      expect(flag.isVeldCarryEnabled, isFalse);
    });

    test('refresh never throws when Firestore is unavailable', () async {
      // No injected Firestore and no Firebase app in the test host.
      final flag = VeldCarryFeatureFlag.forTesting(compileTimeEnabled: true);

      expect(await flag.refresh(), isFalse);
      expect(flag.isVeldCarryEnabled, isFalse);
    });

    test('ensureLoaded never throws and defaults to OFF', () async {
      final flag = VeldCarryFeatureFlag.forTesting(compileTimeEnabled: true);

      await expectLater(flag.ensureLoaded(), completes);
      expect(flag.isVeldCarryEnabled, isFalse);
    });
  });

  test('constants match the admin_config control plane', () {
    expect(VeldCarryFeatureFlag.configCollection, 'admin_config');
    expect(VeldCarryFeatureFlag.configDocument, 'feature_flags');
    expect(VeldCarryFeatureFlag.adminConfigField, 'veldCarryEnabled');
  });
}
