class EmployeeModel {
  final String id;
  final String name;
  final String referencePhotoUrl;
  final OfficeLocation office;

  const EmployeeModel({
    required this.id,
    required this.name,
    required this.referencePhotoUrl,
    required this.office,
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    return EmployeeModel(
      id: json['id'].toString(),
      name: json['name'] as String,
      referencePhotoUrl: json['reference_photo_url'] as String,
      office: OfficeLocation.fromJson(json['office'] as Map<String, dynamic>),
    );
  }
}

class OfficeLocation {
  final double lat;
  final double lng;
  final double radiusMeters;

  const OfficeLocation({
    required this.lat,
    required this.lng,
    required this.radiusMeters,
  });

  factory OfficeLocation.fromJson(Map<String, dynamic> json) {
    return OfficeLocation(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      radiusMeters: (json['radius_meters'] as num).toDouble(),
    );
  }
}
