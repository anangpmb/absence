# Absence — Face Attendance POC

Flutter proof-of-concept for attendance check-in using **face verification + GPS radius + liveness detection**, running 100% on-device via Google MLKit and TFLite (FaceNet).

---

## Check-in Flow

```
┌─────────────────────────────────────────────────────────┐
│  1. Tap "Start Check In"                                │
│           │                                             │
│           ▼                                             │
│  2. GPS radius check                                    │
│     • Get current coordinates (Geolocator)             │
│     • Haversine distance to office location            │
│     • Reject if outside allowed radius                  │
│           │                                             │
│           ▼                                             │
│  3. Load & register reference photo                     │
│     • Download from hosting URL (first time only)      │
│     • Cache locally for 24 hours                        │
│     • Register FaceNet embedding → on-device SQLite    │
│           │                                             │
│           ▼                                             │
│  4. Liveness check                                      │
│     • Challenge 1: Blink both eyes                     │
│     • Challenge 2: Turn head left OR right (random)    │
│     • 15-second timeout per challenge                  │
│           │                                             │
│           ▼                                             │
│  5. Face capture (custom camera UI)                     │
│     • Head silhouette guide overlay                    │
│     • Auto-capture after 1.5 s stable face detection   │
│     • Manual shutter button as fallback                │
│           │                                             │
│           ▼                                             │
│  6. Face verification (on-device, background isolate)  │
│     • FaceNet cosine similarity vs registered photo    │
│     • Threshold: 0.70                                  │
│           │                                             │
│           ▼                                             │
│  7. POST /api/absensi { lat, lng, timestamp }          │
│           │                                             │
│           ▼                                             │
│  8. Home page — attendance record displayed             │
└─────────────────────────────────────────────────────────┘
```

**No biometric data leaves the device.** Face embeddings and matching run entirely on-device. Only the attendance record (timestamp + GPS) is sent to the server.

---

## Project Structure

```
lib/
├── main.dart                          # DI wiring + FaceVerification global init
│
├── models/
│   ├── employee_model.dart            # EmployeeModel + OfficeLocation
│   └── checkin_result.dart            # Immutable result passed to HomePage
│
├── services/                          # Pure Dart — no state, no Flutter coupling
│   ├── reference_photo_service.dart   # Download + 24h local cache (Dio)
│   ├── face_verification_service.dart # face_verification wrapper (FaceNet)
│   └── location_service.dart          # GPS + Haversine radius check
│
├── controllers/
│   └── checkin_controller.dart        # ChangeNotifier state machine ← swap point
│
└── pages/
    ├── checkin_page.dart              # Check-in UI + navigation orchestration
    ├── liveness_check_page.dart       # Blink + head-turn challenge (MLKit stream)
    ├── face_capture_page.dart         # Custom camera + head outline guide
    └── home_page.dart                 # Success screen with attendance info
```

### Controller state machine

```
idle
 └─▶ checkingLocation
      └─▶ downloadingPhoto
           └─▶ preparingCamera
                └─▶ awaitingLiveness    ← page opens LivenessCheckPage
                     └─▶ awaitingVerification  ← page opens FaceCapturePage
                          └─▶ submitting  (verifying + POSTing)
                               └─▶ success ──▶ HomePage
                                   failed  ──▶ retry
```

### State management swap point

Only `checkin_controller.dart` needs to change when moving to a different state management. All services stay the same.

| State management | Migration |
|---|---|
| **ChangeNotifier** (current POC) | No change |
| **Riverpod** | `extends StateNotifier<CheckinState>` + freeze the state class |
| **Bloc** | `extends Bloc<CheckinEvent, CheckinState>` |
| **GetX** | Fields become `Rx<T>` observables |

---

## Dependencies

```yaml
dependencies:
  # On-device face verification — FaceNet (TFLite) + cosine similarity + SQLite
  face_verification: ^0.3.7

  # Direct MLKit access for liveness detection (blink / head-turn)
  google_mlkit_face_detection: ^0.13.2

  camera: ^0.11.0
  geolocator: ^13.0.0
  permission_handler: ^11.3.1
  dio: ^5.7.0
  path_provider: ^2.1.4
  path: ^1.9.0
  http: ^1.2.2
```

---

## Platform Setup

### Android

**`android/app/src/main/AndroidManifest.xml`**

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
```

**`android/app/build.gradle`**

```gradle
android {
    defaultConfig {
        minSdkVersion 21
        compileSdkVersion 34
    }
}
```

### iOS

**`ios/Runner/Info.plist`**

```xml
<key>NSCameraUsageDescription</key>
<string>Used for face verification during attendance check-in</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to verify your location during attendance check-in</string>
```

**`ios/Podfile`** — minimum iOS 11:

```ruby
platform :ios, '11.0'
```

> Always test on a **physical device** — neither MLKit nor TFLite run on simulators.

---

## Sample Data Setup

All sample data is in [`lib/main.dart`](lib/main.dart) inside `_RootState`. Replace these three things before running:

### 1. Employee data

```dart
final EmployeeModel _employee = EmployeeModel(
  id: '1',
  name: 'Your Name Here',

  // URL to a clear, front-facing photo of the employee.
  // Must meet the quality checklist below.
  referencePhotoUrl: 'https://your-storage.com/photos/employee_1.jpg',

  office: const OfficeLocation(
    lat: -6.2088,       // Office latitude
    lng: 106.8456,      // Office longitude
    radiusMeters: 100,  // Allowed check-in radius in metres
  ),
);
```

**Finding office coordinates:** open Google Maps → right-click the office location → the lat/lng appears at the top of the context menu.

### 2. API endpoint & auth token

```dart
_controller = CheckinController(
  // ...services...
  apiBaseUrl: 'https://your-api.example.com',  // No trailing slash
  authToken: 'eyJ...',                          // From your auth flow
);
```

Expected POST body to `{apiBaseUrl}/api/absensi`:

```json
{
  "lat": -6.20880,
  "lng": 106.84560,
  "timestamp": "2025-01-15T08:30:00.000Z"
}
```

Expected success response: HTTP `200` or `201`.

### 3. Reference photo quality checklist

The FaceNet model is sensitive to photo quality. Provide a photo that meets these criteria:

| Criteria | Required |
|---|---|
| Front-facing, both eyes visible | ✓ |
| Solid / plain background | ✓ |
| Minimum 200 × 200 px | ✓ |
| Even lighting, no harsh shadows on face | ✓ |
| No sunglasses, no face mask | ✓ |
| Single face in frame | ✓ |

---

## Face Capture UI

`face_capture_page.dart` provides a custom full-screen camera with:

- **Head silhouette overlay** — a bezier-curve head outline drawn with `CustomPaint` over a dimmed surround. The border changes from white → green when a face is detected.
- **Subtle eye-guide dots** — shown when no face is detected to help the user align.
- **Auto-capture** — after a face is held steady in frame for **1.5 seconds**, the shutter fires automatically.
- **Countdown ring** — a `CircularProgressIndicator` in the top-right shows the hold-still timer.
- **Manual shutter button** — tap at any time as a fallback.

---

## Liveness Detection

Runs before face capture to prevent photo spoofing. Implemented directly via MLKit (not part of the `face_verification` package).

### Challenges

| # | Challenge | Pass condition |
|---|---|---|
| 1 | **Blink** | Eyes open `> 0.7`, then both closed `< 0.2` |
| 2 | **Turn left or right** (random) | `headEulerAngleY` exceeds ±20° |

### Tunable constructor parameters

```dart
LivenessCheckPage(
  cameraDescription: camera,
  blinkThreshold: 0.2,         // Eye-closed threshold (lower = harder)
  eyeOpenThreshold: 0.7,       // Confirmation threshold before blink counts
  headTurnAngle: 20.0,         // Degrees required for head-turn challenge
  frameSkipCount: 6,           // Process every N-th frame (lower = more CPU)
  challengeTimeoutSeconds: 15, // Seconds per challenge before auto-fail
)
```

---

## Face Verification Threshold

Configured in `FaceVerificationService.defaultThreshold`:

| Value | Effect |
|---|---|
| `0.60` | Lenient — easier match, some false positives |
| `0.70` | **Default** — balanced accuracy and UX |
| `0.75+` | Strict — may reject valid matches in poor lighting |

---

## Quick Start

```bash
# 1. Install dependencies
flutter pub get

# 2. Run on a connected physical device
flutter run

# 3. Build release APK
flutter build apk --release
```
