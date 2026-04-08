import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/safezone_model.dart';
import 'data_service.dart';
import 'notification_service.dart';

class SafeZoneService {
  static final SafeZoneService _i = SafeZoneService._();
  factory SafeZoneService() => _i;
  SafeZoneService._();

  static const Duration _checkInterval = Duration(seconds: 30);
  static const Duration _confirmTimeout = Duration(minutes: 2);

  Timer? _pollTimer;
  Timer? _confirmTimer;
  String? _currentElderlyId;
  String? get currentElderlyId => _currentElderlyId;
  bool _running = false;
  // In-memory flag: true while waiting for the elderly's "I'm OK" response.
  // Avoids a Firestore read every 30 s when we already know confirmation is pending.
  bool _awaitingConfirmation = false;

  void Function()? _inAppCallback;
  void setInAppCheckCallback(void Function()? cb) => _inAppCallback = cb;

  void start(String elderlyId) {
    if (_running && _currentElderlyId == elderlyId) return;
    stop();
    _currentElderlyId = elderlyId;
    _running = true;
    _checkOnce();
    _pollTimer = Timer.periodic(_checkInterval, (_) => _checkOnce());
    debugPrint('[SafeZone] monitoring started for $elderlyId');
  }

  void stop() {
    _pollTimer?.cancel();
    _confirmTimer?.cancel();
    _pollTimer = null;
    _confirmTimer = null;
    _running = false;
    _currentElderlyId = null;
    _awaitingConfirmation = false;
    debugPrint('[SafeZone] monitoring stopped');
  }

  Future<void> confirmSafe() async {
    _confirmTimer?.cancel();
    _confirmTimer = null;
    _awaitingConfirmation = false;   // clear in-memory flag immediately
    final id = _currentElderlyId;
    if (id == null) return;
    final settings = await DataService().getSafeZone(id);
    if (settings == null) return;
    await DataService().saveSafeZone(settings.copyWith(awaitingConfirmation: false));
    await NotificationService().cancelElderlyCheck();
    debugPrint('[SafeZone] elderly confirmed safe');
  }

  /// Public method called by the test alarm button in Settings.
  /// Forces an immediate breach check regardless of the polling timer.
  Future<void> triggerTestCheck(String elderlyId) async {
    _currentElderlyId = elderlyId;
    _awaitingConfirmation = false;
    await _checkOnce();
  }

  Future<void> _checkOnce() async {
    final id = _currentElderlyId;
    if (id == null) return;
    // Fast in-memory guard — skip the Firestore read entirely while we are
    // already waiting for the elderly to confirm.  Saves 1 read every 30 s
    // during the 2-minute confirmation window.
    if (_awaitingConfirmation) return;
    final settings = await DataService().getSafeZone(id);
    if (settings == null || !settings.enabled || !settings.hasHome) return;
    if (settings.awaitingConfirmation) {
      _awaitingConfirmation = true; // sync in-memory with persisted state
      return;
    }
    if (!settings.isAbnormalTime) return;

    final Position? pos = await _getPosition();
    if (pos == null && settings.radiusMeters != -1) return;

    final distanceM = pos == null
        ? 99999.0 // Guaranteed to be > -1
        : _haversineMeters(
            pos.latitude, pos.longitude, settings.homeLat!, settings.homeLng!,
          );
    debugPrint('[SafeZone] dist=${distanceM.toStringAsFixed(1)}m radius=${settings.radiusMeters}m');

    if (distanceM > settings.radiusMeters) {
      await _triggerElderlyCheck(settings);
    }
  }

  Future<void> _triggerElderlyCheck(SafeZoneSettings settings) async {
    _awaitingConfirmation = true;  // set in-memory immediately — no more Firestore reads until resolved
    await DataService().saveSafeZone(settings.copyWith(awaitingConfirmation: true));
    _inAppCallback?.call();
    await NotificationService().showElderlyCheckNotification();

    _confirmTimer?.cancel();
    _confirmTimer = Timer(_confirmTimeout, () async {
      final latest = await DataService().getSafeZone(settings.elderlyId);
      if (latest == null) return;
      if (latest.awaitingConfirmation) {
        await DataService().saveSafeZone(latest.copyWith(awaitingConfirmation: false));
        await NotificationService().showCaregiverAlert(
          title: '⚠️ Safe Zone Alert',
          body: 'Your elderly has left the safe area during unusual hours and has not responded.',
        );
        debugPrint('[SafeZone] caregiver alerted — no response from elderly');
      }
    });
  }

  Future<Position?> _getPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return null;
      }
      if (perm == LocationPermission.deniedForever) return null;
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      return pos;
    } catch (e) {
      debugPrint('[SafeZone] location error: $e');
      return null;
    }
  }

  double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final dPhi = (lat2 - lat1) * pi / 180;
    final dLam = (lng2 - lng1) * pi / 180;
    final a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLam / 2) * sin(dLam / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
