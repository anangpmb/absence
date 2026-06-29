class CheckinResult {
  final String employeeName;
  final DateTime checkinTime;
  final double lat;
  final double lng;
  final double distanceMeters;
  final double officeRadiusMeters;

  const CheckinResult({
    required this.employeeName,
    required this.checkinTime,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
    required this.officeRadiusMeters,
  });
}
