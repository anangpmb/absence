import 'package:camera/camera.dart';
import 'package:face_verification/face_verification.dart';

class FaceVerificationService {
  /// Cosine similarity threshold. Higher = stricter matching.
  static const double defaultThreshold = 0.70;

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
    await FaceVerification.instance.registerFromImagePath(
      id: employeeId,
      imagePath: referencePhotoPath,
      imageId: 'reference_photo',
      name: employeeName,
      replace: true,
    );
  }

  /// Verifies [photoPath] against the registered embedding for [employeeId].
  /// Returns the matched ID on success, or null if the face doesn't match.
  /// Runs in a background isolate so the UI stays responsive.
  Future<String?> verifyPhoto({
    required String photoPath,
    required String employeeId,
  }) async {
    return FaceVerification.instance.verifyFromImagePathIsolate(
      imagePath: photoPath,
      threshold: defaultThreshold,
      staffId: employeeId,
    );
  }

  CameraDescription get frontCamera {
    final cam = _frontCamera;
    if (cam == null) throw StateError('Call initialize() before frontCamera.');
    return cam;
  }

  bool get isInitialized => _frontCamera != null;
}
