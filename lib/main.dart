import 'package:face_verification/face_verification.dart';
import 'package:flutter/material.dart';

import 'controllers/checkin_controller.dart';
import 'models/employee_model.dart';
import 'pages/checkin_page.dart';
import 'services/face_verification_service.dart';
import 'services/location_service.dart';
import 'services/reference_photo_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the TFLite FaceNet model + SQLite embedding store once.
  // This must complete before any verification calls.
  await FaceVerification.instance.init();

  runApp(const AbsenceApp());
}

class AbsenceApp extends StatelessWidget {
  const AbsenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Absence',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const _Root(),
    );
  }
}

/// Wires dependencies and hands them to CheckinPage.
///
/// In a real app this wiring lives in your DI layer
/// (e.g. ProviderScope overrides, Riverpod providers, GetIt registrations).
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late final CheckinController _controller;

  // ---------------------------------------------------------------------------
  // POC employee — replace with a real API call / auth flow
  // ---------------------------------------------------------------------------
  final EmployeeModel _employee = EmployeeModel(
    id: '1',
    name: 'Anang Pambudi',
    referencePhotoUrl: 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRSrsimUFsYDrVr2Je8gg0NjeMgkKgps2Wn7OW6UTaogQ&s=10',
    office: const OfficeLocation(
      lat: -6.985997,   // Jakarta — replace with your office lat
      lng: 110.4130644,  // Replace with your office lng
      radiusMeters: 500,
    ),
  );

  @override
  void initState() {
    super.initState();
    _controller = CheckinController(
      referencePhotoService: ReferencePhotoService(),
      faceVerificationService: FaceVerificationService(),
      locationService: LocationService(),
      apiBaseUrl: 'https://your-api.example.com',  // replace
      authToken: 'your-token-here',                // replace
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CheckinPage(
      controller: _controller,
      employee: _employee,
    );
  }
}
