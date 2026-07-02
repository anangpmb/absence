import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/employee_model.dart';
import '../models/checkin_result.dart';
import '../services/reference_photo_service.dart';
import '../services/face_verification_service.dart';
import '../services/location_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum CheckinStatus {
  idle,
  checkingLocation,
  downloadingPhoto,
  preparingCamera,

  /// UI should open [LivenessCheckPage] and call [completeLiveness].
  awaitingLiveness,

  /// UI should open [FaceCapturePage] and call [completeCapture].
  awaitingVerification,

  /// Face matched — submitting record to API.
  submitting,

  success,
  failed,
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------
// Uses ChangeNotifier for the POC.
//
// To migrate to another state management:
//   • Riverpod  → convert to StateNotifier<CheckinState> + freeze the state
//   • Bloc       → convert to Bloc<CheckinEvent, CheckinState>
//   • GetX       → convert fields to Rx<T> observables
//
// Services (injected via constructor) are pure Dart — unchanged regardless
// of which state management layer you choose.

class CheckinController extends ChangeNotifier {
  CheckinController({
    required this.referencePhotoService,
    required this.faceVerificationService,
    required this.locationService,
    required this.apiBaseUrl,
    required this.authToken,
  });

  final ReferencePhotoService referencePhotoService;
  final FaceVerificationService faceVerificationService;
  final LocationService locationService;
  final String apiBaseUrl;
  final String authToken;

  // ---------------------------------------------------------------------------
  // Readable state
  // ---------------------------------------------------------------------------

  CheckinStatus status = CheckinStatus.idle;
  String statusMessage = 'Ready to check in';
  String? errorMessage;
  CheckinResult? result;

  /// Cosine similarity score from the last verification attempt, null if not
  /// yet attempted. Available on both success and failed states.
  double? similarityScore;

  /// Available when status == awaitingLiveness or awaitingVerification.
  CameraDescription? pendingCamera;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    await faceVerificationService.initialize();
  }

  // ---------------------------------------------------------------------------
  // Phase 1: validate location + register reference photo
  // ---------------------------------------------------------------------------

  Future<void> startCheckin(EmployeeModel employee) async {
    if (status != CheckinStatus.idle && status != CheckinStatus.failed) return;

    _clearError();
    _setStatus(CheckinStatus.checkingLocation, 'Checking location...');

    try {
      // Step 1 — GPS radius check
      final locationResult = await locationService.checkRadius(
        officeLat: employee.office.lat,
        officeLng: employee.office.lng,
        maxRadiusMeters: employee.office.radiusMeters,
      );

      // if (!locationResult.isWithinRadius) {
      //   final dist = locationResult.distanceMeters.toStringAsFixed(0);
      //   final max = employee.office.radiusMeters.toStringAsFixed(0);
      //   throw _CheckinException(
      //     'You are ${dist}m from the office (max ${max}m).',
      //   );
      // }

      _pendingLocation = locationResult;
      _pendingEmployee = employee;

      // Step 2 — download / load cached reference photo
      _setStatus(CheckinStatus.downloadingPhoto, 'Loading face data...');

      final localPhotoPath = await referencePhotoService.getLocalReferencePhoto(
        photoUrl: employee.referencePhotoUrl,
        employeeId: employee.id,
      );

      // Step 3 — register embedding with face_verification (SQLite store)
      _setStatus(CheckinStatus.preparingCamera, 'Preparing camera...');

      await faceVerificationService.registerReferenceUser(
        referencePhotoPath: localPhotoPath,
        employeeId: employee.id,
        employeeName: employee.name,
      );

      // Step 4 — signal UI to open liveness check
      pendingCamera = faceVerificationService.frontCamera;
      _setStatus(CheckinStatus.awaitingLiveness, 'Liveness check...');
    } on _CheckinException catch (e) {
      _fail(e.message);
    } on ReferencePhotoException {
      _fail('Could not load reference photo. Check your internet connection.');
    } on LocationPermissionDeniedException catch (e) {
      _fail('Location access required: ${e.reason}');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('face') || msg.contains('detection') || msg.contains('no face')) {
        _fail('No face detected in your reference photo. Please contact your admin.');
      } else {
        _fail('Unexpected error. Please try again. $e');
      }
      debugPrint('CheckinController.startCheckin: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 2: called by UI after LivenessCheckPage returns
  // ---------------------------------------------------------------------------

  void completeLiveness(bool? passed) {
    if (status != CheckinStatus.awaitingLiveness) return;

    if (passed != true) {
      _fail(passed == false
          ? 'Liveness check timed out. Please try again.'
          : 'Liveness check cancelled.');
      return;
    }

    _setStatus(CheckinStatus.awaitingVerification, 'Take a selfie...');
  }

  // ---------------------------------------------------------------------------
  // Phase 3: called by UI after FaceCapturePage returns a photo path
  // ---------------------------------------------------------------------------

  Future<void> completeCapture(String? photoPath) async {
    if (status != CheckinStatus.awaitingVerification) return;

    if (photoPath == null) {
      _fail('Photo capture cancelled.');
      return;
    }

    _setStatus(CheckinStatus.submitting, 'Verifying face...');

    try {
      final verifyResult = await faceVerificationService.verifyPhoto(
        photoPath: photoPath,
        employeeId: _pendingEmployee!.id,
      );

      similarityScore = verifyResult.similarityScore;

      if (!verifyResult.isMatch) {
        _fail('Face not recognized. Ensure good lighting and try again.');
        return;
      }

      _setStatus(CheckinStatus.submitting, 'Saving attendance...');
      // await _submitToApi();

      result = CheckinResult(
        employeeName: _pendingEmployee!.name,
        checkinTime: DateTime.now(),
        lat: _pendingLocation!.currentLat,
        lng: _pendingLocation!.currentLng,
        distanceMeters: _pendingLocation!.distanceMeters,
        officeRadiusMeters: _pendingEmployee!.office.radiusMeters,
        similarityScore: verifyResult.similarityScore,  // double?
      );

      _setStatus(CheckinStatus.success, 'Check-in successful!');
    } on _CheckinException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Verification failed. Please try again. $e');
      debugPrint('CheckinController.completeCapture: $e');
    }
  }

  void reset() {
    status = CheckinStatus.idle;
    statusMessage = 'Ready to check in';
    errorMessage = null;
    result = null;
    similarityScore = null;
    pendingCamera = null;
    _pendingLocation = null;
    _pendingEmployee = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  LocationCheckResult? _pendingLocation;
  EmployeeModel? _pendingEmployee;

  Future<void> _submitToApi() async {
    final loc = _pendingLocation!;

    final response = await http.post(
      Uri.parse('$apiBaseUrl/api/absensi'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'lat': loc.currentLat,
        'lng': loc.currentLng,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw _CheckinException(
        body['message'] as String? ?? 'Server rejected the attendance record.',
      );
    }
  }

  void _setStatus(CheckinStatus s, String message) {
    status = s;
    statusMessage = message;
    notifyListeners();
  }

  void _fail(String message) {
    status = CheckinStatus.failed;
    statusMessage = 'Check-in failed';
    errorMessage = message;
    notifyListeners();
  }

  void _clearError() => errorMessage = null;
}

class _CheckinException implements Exception {
  final String message;
  const _CheckinException(this.message);
}
