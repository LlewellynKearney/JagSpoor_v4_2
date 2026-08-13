import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/outfitter_mode/data/models/client_profile.dart';
import 'package:jagspoor/features/outfitter_mode/data/models/guided_hunt_log.dart';

void main() {
  group('ClientProfile serialization', () {
    test('round-trips through toMap/fromFirestore', () {
      final now = DateTime.utc(2026, 8, 13, 10, 0, 0);
      final client = ClientProfile(
        id: 'client-1',
        outfitterId: 'outfitter-1',
        fullName: 'John Hunter',
        idPassportNumber: 'A123456789',
        nationality: 'South African',
        cellNumber: '+27821234567',
        email: 'john@example.com',
        address: '1 Game Rd, Polokwane',
        assignedPackageId: 'pkg-1',
        assignedPackageName: 'Kudu Plains Package',
        assignedBookingId: 'booking-1',
        permitReferenceIds: const ['permit-a', 'permit-b'],
        notes: 'Repeat client',
        createdAt: now,
        updatedAt: now,
      );
      final map = client.toMap();
      final restored = ClientProfile.fromMap(map, id: 'client-1');
      expect(restored.id, 'client-1');
      expect(restored.outfitterId, 'outfitter-1');
      expect(restored.fullName, 'John Hunter');
      expect(restored.idPassportNumber, 'A123456789');
      expect(restored.nationality, 'South African');
      expect(restored.cellNumber, '+27821234567');
      expect(restored.email, 'john@example.com');
      expect(restored.assignedPackageId, 'pkg-1');
      expect(restored.assignedPackageName, 'Kudu Plains Package');
      expect(restored.assignedBookingId, 'booking-1');
      expect(restored.permitReferenceIds, ['permit-a', 'permit-b']);
      expect(restored.notes, 'Repeat client');
      expect(restored.createdAt!.toUtc(), now);
      expect(restored.updatedAt!.toUtc(), now);
    });

    test('fromFirestore tolerates missing fields', () {
      final restored = ClientProfile.fromMap(const <String, dynamic>{}, id: 'c');
      expect(restored.fullName, '');
      expect(restored.idPassportNumber, '');
      expect(restored.permitReferenceIds, isEmpty);
      expect(restored.outfitterId, '');
    });

    test('copyWith updates fields and bumps updatedAt', () {
      final original = ClientProfile(
        id: 'c',
        outfitterId: 'o',
        fullName: 'Old Name',
      );
      final updated = original.copyWith(fullName: 'New Name');
      expect(updated.fullName, 'New Name');
      expect(updated.id, 'c');
      expect(updated.outfitterId, 'o');
      expect(updated.updatedAt, isNotNull);
    });
  });

  group('GuidedHuntLog serialization', () {
    test('round-trips through toMap/fromFirestore', () {
      final hunt = DateTime.utc(2026, 8, 12, 6, 0, 0);
      final log = GuidedHuntLog(
        id: 'log-1',
        outfitterId: 'outfitter-1',
        clientId: 'client-1',
        clientName: 'John Hunter',
        clientIdPassport: 'A123456789',
        bookingId: 'booking-1',
        species: 'Kudu',
        sex: 'Male',
        carcassWeightKg: 85.4,
        shotLocationDescription: 'Kudu pan, north fence',
        shotLat: -23.5,
        shotLng: 28.1,
        trophyMeasurementInches: 52.3,
        trophyMeasurementLabel: 'horn length',
        trophyPhotoUrls: const ['https://img/1.jpg'],
        shotPlacement: 'Broadside - heart/lung',
        rifleCalibreMm: 7.0,
        distanceMeters: 180.0,
        permitId: 'permit-1',
        carcassRecordId: 'carcass-1',
        notes: 'One-shot drop',
        huntDate: hunt,
        createdAt: hunt,
        updatedAt: hunt,
      );
      final restored = GuidedHuntLog.fromMap(log.toMap(), id: 'log-1');
      expect(restored.id, 'log-1');
      expect(restored.outfitterId, 'outfitter-1');
      expect(restored.clientId, 'client-1');
      expect(restored.clientName, 'John Hunter');
      expect(restored.clientIdPassport, 'A123456789');
      expect(restored.bookingId, 'booking-1');
      expect(restored.species, 'Kudu');
      expect(restored.sex, 'Male');
      expect(restored.carcassWeightKg, 85.4);
      expect(restored.shotLocationDescription, 'Kudu pan, north fence');
      expect(restored.shotLat, -23.5);
      expect(restored.shotLng, 28.1);
      expect(restored.trophyMeasurementInches, 52.3);
      expect(restored.trophyMeasurementLabel, 'horn length');
      expect(restored.trophyPhotoUrls, ['https://img/1.jpg']);
      expect(restored.shotPlacement, 'Broadside - heart/lung');
      expect(restored.rifleCalibreMm, 7.0);
      expect(restored.distanceMeters, 180.0);
      expect(restored.permitId, 'permit-1');
      expect(restored.carcassRecordId, 'carcass-1');
      expect(restored.notes, 'One-shot drop');
      expect(restored.huntDate.toUtc(), hunt);
    });

    test('fromFirestore tolerates missing fields and falls back for huntDate',
        () {
      final restored = GuidedHuntLog.fromMap(const <String, dynamic>{}, id: 'log');
      expect(restored.species, 'Unknown');
      expect(restored.sex, 'Unknown');
      expect(restored.carcassWeightKg, 0.0);
      expect(restored.trophyPhotoUrls, isEmpty);
      expect(restored.huntDate, isNotNull); // falls back to now
    });

    test('copyWith links permit/carcass ids and bumps updatedAt', () {
      final original = GuidedHuntLog(
        id: 'log',
        outfitterId: 'o',
        clientId: 'c',
        clientName: 'C',
        species: 'Impala',
        huntDate: DateTime.now(),
      );
      final linked =
          original.copyWith(permitId: 'permit-2', carcassRecordId: 'carc-2');
      expect(linked.permitId, 'permit-2');
      expect(linked.carcassRecordId, 'carc-2');
      expect(linked.species, 'Impala'); // unchanged
      expect(linked.updatedAt, isNotNull);
    });
  });
}
