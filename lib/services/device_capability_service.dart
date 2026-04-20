import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Checks whether the device is ready for live/streaming features.
///
/// Verifies:
/// - Camera permission
/// - Microphone permission
/// - Network connectivity
class DeviceCapabilityService {
  DeviceCapabilityService._();
  static final instance = DeviceCapabilityService._();

  bool _cameraGranted = false;
  bool _microphoneGranted = false;
  bool _hasConnection = false;

  Future<bool> checkCapabilities() async {
    developer.log('Checking device capabilities', name: 'WEAFRICA.Device');

    if (kIsWeb) {
      // permission_handler does not support web in the same way; treat as granted.
      _cameraGranted = true;
      _microphoneGranted = true;
    } else {
      _cameraGranted = await _isGranted(Permission.camera);
      _microphoneGranted = await _isGranted(Permission.microphone);
    }

    _hasConnection = await _checkHasConnection();

    final ready = _cameraGranted && _microphoneGranted && _hasConnection;

    developer.log(
      'Device ready=$ready (camera=$_cameraGranted, mic=$_microphoneGranted, connection=$_hasConnection)',
      name: 'WEAFRICA.Device',
    );

    return ready;
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;

    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    _cameraGranted = cameraStatus.isGranted;
    _microphoneGranted = micStatus.isGranted;

    return _cameraGranted && _microphoneGranted;
  }

  bool get canStream => _cameraGranted && _microphoneGranted && _hasConnection;

  String get missingRequirements {
    if (!_hasConnection) return 'Internet connection needed';
    if (!_cameraGranted && !_microphoneGranted) return 'Camera and microphone access needed';
    if (!_cameraGranted) return 'Camera access needed';
    if (!_microphoneGranted) return 'Microphone access needed';
    return '';
  }

  Future<bool> _isGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted;
  }

  Future<bool> _checkHasConnection() async {
    try {
      final dynamic result = await Connectivity().checkConnectivity();
      if (result is ConnectivityResult) {
        return result != ConnectivityResult.none;
      }
      if (result is List<ConnectivityResult>) {
        if (result.isEmpty) return false;
        return result.any((r) => r != ConnectivityResult.none);
      }
      return true;
    } catch (_) {
      return true;
    }
  }
}
