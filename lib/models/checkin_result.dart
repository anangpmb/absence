class CheckinResult {
  final String employeeName;
  final DateTime checkinTime;
  final double lat;
  final double lng;
  final double distanceMeters;
  final double officeRadiusMeters;

  /// Cosine similarity score between the captured selfie and the reference
  /// photo, in [0.0, 1.0]. Null when the score was unavailable (shouldn't
  /// happen on the success path, but kept nullable for safety).
  final double? similarityScore;

  const CheckinResult({
    required this.employeeName,
    required this.checkinTime,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
    required this.officeRadiusMeters,
    this.similarityScore,
  });
}
