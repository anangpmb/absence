import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ReferencePhotoService {
  static const int _cacheDurationHours = 24;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  /// Returns local path to the reference photo.
  /// Downloads from [photoUrl] on first call or after cache expires.
  Future<String> getLocalReferencePhoto({
    required String photoUrl,
    required String employeeId,
  }) async {
    final cachedFile = await _getCachedFile(employeeId);

    if (await _isCacheValid(cachedFile)) {
      return cachedFile.path;
    }

    return await _downloadAndCache(url: photoUrl, destinationFile: cachedFile);
  }

  /// Call this after a profile photo update to force a re-download.
  Future<void> clearCache(String employeeId) async {
    final cachedFile = await _getCachedFile(employeeId);
    if (await cachedFile.exists()) {
      await cachedFile.delete();
    }
  }

  Future<File> _getCachedFile(String employeeId) async {
    final cacheDir = await getTemporaryDirectory();
    return File(path.join(cacheDir.path, 'ref_face_$employeeId.jpg'));
  }

  Future<bool> _isCacheValid(File file) async {
    if (!await file.exists()) return false;
    final age = DateTime.now().difference(await file.lastModified());
    return age.inHours < _cacheDurationHours;
  }

  Future<String> _downloadAndCache({
    required String url,
    required File destinationFile,
  }) async {
    try {
      await _dio.download(url, destinationFile.path);
      if (!await destinationFile.exists()) {
        throw ReferencePhotoException('File not saved to cache after download.');
      }
      return destinationFile.path;
    } on DioException catch (e) {
      throw ReferencePhotoException('Download failed: ${e.message}');
    }
  }
}

class ReferencePhotoException implements Exception {
  final String message;
  const ReferencePhotoException(this.message);

  @override
  String toString() => 'ReferencePhotoException: $message';
}
