// ignore_for_file: avoid_print, unused_import
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
typedef DiagnosticResult = ({bool pass, String message});
class FirebaseDiagnostic {
  static final _auth = FirebaseAuth.instance;
  static final _firestore = FirebaseFirestore.instance;
  final List<DiagnosticResult> _results = [];
  void _log(bool pass, String msg) => _results.add((pass: pass, message: msg));
  Future<DiagnosticResult> _wrap(String name, Future<dynamic> Function() fn) async {
    try {
      await fn(); _log(true, '[PASS] $name'); return (pass: true, message: '[PASS] $name');
    } on FirebaseException catch (e) {
      final msg = '[FAIL] $name: ${e.code} - ${e.message}'; _log(false, msg); return (pass: false, message: msg);
    } catch (e) {
      final msg = '[FAIL] $name: $e'; _log(false, msg); return (pass: false, message: msg);
    }
  }
  Future<List<DiagnosticResult>> run() async {
    print('════ Firebase Diagnostics ════');
    final uid = _auth.currentUser?.uid;
    if (uid == null) { _log(false, '[FAIL] Auth check: No user logged in'); return _results; }
    _log(true, '[PASS] Auth check: uid=$uid');
    await _wrap('User Profile: users/$uid', () => _firestore.collection('users').doc(uid).get());
    final firearmsSnap = await _firestore.collection('firearms').where('ownerId', isEqualTo: uid).limit(1).get();
    if (firearmsSnap.docs.isEmpty) { _log(false, '[FAIL] Firearm Safe: No firearms found'); } else {
      _log(true, '[PASS] Firearm Safe: Found items');
      final fid = firearmsSnap.docs.first.id;
      await _wrap('Ammunition Sub-collection: firearms/$fid/ammunition', () => _firestore.collection('firearms/$fid/ammunition').limit(1).get());
    }
    await _wrap('Catalog: factory_ammunition', () => _firestore.collection('factory_ammunition').limit(1).get());
    await _wrap('Catalog: bullets', () => _firestore.collection('bullets').limit(1).get());
    await _wrap('Catalog: propellants', () => _firestore.collection('propellants').limit(1).get());
    await _wrap('Outfitter: bookings', () => _firestore.collection('outfitter').doc('bookings').collection('records').limit(1).get());
    await _wrap('Outfitter: lodging', () => _firestore.collection('outfitter').doc('lodging').collection('units').limit(1).get());
    await _wrap('Outfitter: fleet', () => _firestore.collection('outfitter').doc('fleet').collection('assets').limit(1).get());
    final fails = _results.where((r) => !r.pass);
    print('── Results: ${_results.length - fails.length}/${_results.length} passed ──');
    for (var r in _results) { print(r.message); }
    print('════ End Diagnostics ════');
    return _results;
  }
}
