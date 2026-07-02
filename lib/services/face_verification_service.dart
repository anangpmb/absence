import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:face_verification/face_verification.dart';
// ignore: implementation_imports
import 'package:face_verification/src/services/isolate_verification_worker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class FaceVerifyResult {
  final String? matchedId;

  /// Cosine similarity score in [0.0, 1.0]. Higher = more similar.
  /// Is null when the score could not be computed (e.g., no face detected,
  /// worker error). Only non-null when a face was actually found and compared.
  final double? similarityScore;

  const FaceVerifyResult({required this.matchedId, required this.similarityScore});

  bool get isMatch => matchedId != null;
}

class FaceVerificationService {
  /// Cosine similarity threshold. Higher = stricter matching.
  static const double defaultThreshold = 0.70;

  static const String _modelAsset =
      'packages/face_verification/assets/models/facenet.tflite';

  /// Bundled facenet.tflite uses 160×160 input (the original FaceNet size).
  /// Using 112 causes the reshaping padding to hit `0 (int) as double`,
  /// which throws at runtime.
  static const int _modelInputSize = 160;

  CameraDescription? _frontCamera;

  /// Resolves the front camera. Call during the check-in flow before capture.
  /// [FaceVerification.instance.init()] must already have been called in main().
  Future<void> initialize() async {
    if (_frontCamera != null) return;
    final cameras = await availableCameras();
    _frontCamera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
  }

  /// Registers (or refreshes) the employee's reference photo in the local
  /// SQLite store. Safe to call with [replace: true] on every session —
  /// it overwrites the old embedding when the cached photo changes.
  Future<void> registerReferenceUser({
    required String referencePhotoPath,
    required String employeeId,
    String? employeeName,
  }) async {
    // The package's registerFromImagePath throws when a record with the same
    // id+imageId already exists, even when replace:true is passed — the guard
    // fires before the upsert. Delete first so retries always succeed.
    await FaceVerification.instance.deleteFaceRecord(employeeId, 'reference_photo');
    await FaceVerification.instance.registerFromImagePath(
      id: employeeId,
      imagePath: referencePhotoPath,
      imageId: 'reference_photo',
      name: employeeName,
      replace: true,
    );
  }

  /// Verifies [photoPath] against the registered embedding for [employeeId].
  ///
  /// Returns a [FaceVerifyResult] with:
  /// - [matchedId]: non-null on success, null when face not recognized
  /// - [similarityScore]: the actual cosine similarity (0.0–1.0) when a face
  ///   was detected and compared; null when no face was found or an error
  ///   occurred in the isolate.
  ///
  /// Throws when the isolate worker encounters a fatal error (e.g., model
  /// load failure, DB unavailable). Those failures are distinct from a low
  /// similarity score and should not be shown as "Face not recognized."
  Future<FaceVerifyResult> verifyPhoto({
    required String photoPath,
    required String employeeId,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'face_verification.db');

    final rootIsolateToken = ServicesBinding.rootIsolateToken;
    if (rootIsolateToken == null) {
      throw StateError(
          'RootIsolateToken is null. Call verifyPhoto from the main isolate.');
    }

    final modelData = await rootBundle.load(_modelAsset);
    final modelBytes = modelData.buffer.asUint8List();

    final result = await compute(isolateVerificationWorker, {
      'imagePath': photoPath,
      'dbPath': dbPath,
      'threshold': defaultThreshold,
      'staffId': employeeId,
      'modelBytes': modelBytes,
      'rootIsolateToken': rootIsolateToken,
      'modelInputSize': _modelInputSize,
    });

    if (result['success'] != true) {
      // The isolate threw — surface the actual error rather than hiding it
      final error = result['error'] as String? ?? 'Unknown error in verification worker';
      debugPrint('[FaceVerificationService] worker error: $error');
      throw Exception(error);
    }

    final reason = result['reason'] as String?;

    // No face was found in the captured photo
    if (reason == 'No face detected') {
      throw Exception('No face detected. Make sure your face is clearly visible and the photo is well-lit.');
    }

    // No reference registered yet (shouldn't happen in normal flow)
    if (reason == 'No registered faces in database') {
      throw Exception('Reference face not found. Please restart the check-in process.');
    }

    final bestScore = (result['bestScore'] as num).toDouble();
    return FaceVerifyResult(
      matchedId: result['matchId'] as String?,
      // Only expose the score when a real comparison happened (score > 0)
      similarityScore: bestScore > 0 ? bestScore : null,
    );
  }

  CameraDescription get frontCamera {
    final cam = _frontCamera;
    if (cam == null) throw StateError('Call initialize() before frontCamera.');
    return cam;
  }

  bool get isInitialized => _frontCamera != null;
}
