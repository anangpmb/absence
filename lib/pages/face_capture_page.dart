import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Custom camera page that guides the user to position their face inside a
/// head-shaped outline, then auto-captures once a face is stable in frame.
///
/// Pops with the captured photo's file path on success, or null on cancel.
class FaceCapturePage extends StatefulWidget {
  const FaceCapturePage({super.key, required this.cameraDescription});

  final CameraDescription cameraDescription;

  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage>
    with WidgetsBindingObserver {
  // ---------------------------------------------------------------------------
  // Camera & face detector
  // ---------------------------------------------------------------------------

  CameraController? _camera;
  late final FaceDetector _detector;

  bool _isBusy = false;
  int _frameCount = 0;

  // ---------------------------------------------------------------------------
  // UI state
  // ---------------------------------------------------------------------------

  bool _faceDetected = false;
  bool _capturing = false;

  /// When the face first entered the guide. Used for the auto-capture countdown.
  DateTime? _faceEnteredAt;

  static const _autoCaptureDuration = Duration(milliseconds: 1500);
  static const _frameSkip = 5;

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        // No classification needed — just presence detection for the guide
      ),
    );
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      cam.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  Future<void> _initCamera() async {
    final cam = CameraController(
      widget.cameraDescription,
      ResolutionPreset.high,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
      enableAudio: false,
    );

    await cam.initialize();
    if (!mounted) return;

    _camera = cam;
    setState(() {});
    cam.startImageStream(_onFrame);
  }

  // ---------------------------------------------------------------------------
  // Frame processing — face presence detection for guide feedback
  // ---------------------------------------------------------------------------

  Future<void> _onFrame(CameraImage image) async {
    _frameCount++;
    if (_frameCount % _frameSkip != 0) return;
    if (_isBusy || _capturing) return;

    _isBusy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;

      final faces = await _detector.processImage(input);
      final detected = faces.isNotEmpty;

      if (detected != _faceDetected) {
        if (mounted) {
          setState(() {
            _faceDetected = detected;
            _faceEnteredAt = detected ? DateTime.now() : null;
          });
        }
      }

      // Auto-capture once the face has been stable in frame long enough
      if (detected && _faceEnteredAt != null) {
        final held = DateTime.now().difference(_faceEnteredAt!);
        if (held >= _autoCaptureDuration) {
          await _capturePhoto();
        }
      }
    } finally {
      _isBusy = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  Future<void> _capturePhoto() async {
    if (_capturing) return;
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;

    setState(() => _capturing = true);

    try {
      await cam.stopImageStream();
      final picture = await cam.takePicture();
      if (mounted) Navigator.of(context).pop(picture.path);
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
      // Resume stream so the user can try the manual button again
      await _camera?.startImageStream(_onFrame);
    }
  }

  // ---------------------------------------------------------------------------
  // InputImage conversion
  // ---------------------------------------------------------------------------

  InputImage? _toInputImage(CameraImage image) {
    final sensorOrientation = widget.cameraDescription.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      final deviceRot = _orientations[_camera?.value.deviceOrientation] ?? 0;
      final compensated = (sensorOrientation + deviceRot) % 360;
      rotation = InputImageRotationValue.fromRawValue(compensated);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
    if (image.planes.length != 1) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    final ready = cam != null && cam.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ready ? _buildCamera(cam) : _buildLoading(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _buildCamera(CameraController cam) {
    final size = MediaQuery.of(context).size;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-screen preview
        _CameraPreviewFill(controller: cam, screenSize: size),

        // Head outline guide with dimmed surround
        _HeadGuideOverlay(faceDetected: _faceDetected),

        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  style: IconButton.styleFrom(backgroundColor: Colors.black38),
                ),
                if (_faceDetected && !_capturing)
                  _CountdownIndicator(
                    startedAt: _faceEnteredAt!,
                    duration: _autoCaptureDuration,
                  ),
              ],
            ),
          ),
        ),

        // Bottom panel — instruction + manual button
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: _BottomPanel(
              faceDetected: _faceDetected,
              capturing: _capturing,
              onCapture: _capturePhoto,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Head guide overlay
// ---------------------------------------------------------------------------

class _HeadGuideOverlay extends StatelessWidget {
  const _HeadGuideOverlay({required this.faceDetected});
  final bool faceDetected;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HeadSilhouettePainter(faceDetected: faceDetected),
    );
  }
}

class _HeadSilhouettePainter extends CustomPainter {
  const _HeadSilhouettePainter({required this.faceDetected});
  final bool faceDetected;

  @override
  void paint(Canvas canvas, Size size) {
    final headPath = _buildHeadPath(size);

    // ── Dimmed surround ─────────────────────────────────────────────────────
    final overlay = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addPath(headPath, Offset.zero)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(overlay, Paint()..color = Colors.black.withValues(alpha: 0.55));

    // ── Head outline border ─────────────────────────────────────────────────
    canvas.drawPath(
      headPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = faceDetected ? Colors.greenAccent : Colors.white70,
    );

    // ── Subtle eye-position guide dots ──────────────────────────────────────
    if (!faceDetected) {
      _drawEyeGuides(canvas, size);
    }
  }

  /// Builds a human head silhouette path.
  /// Wide at the crown/temples, narrowing smoothly to a rounded chin.
  Path _buildHeadPath(Size size) {
    final cx = size.width / 2;
    final w = size.width * 0.58;
    final h = size.height * 0.52;
    final top = size.height * 0.10;
    final bottom = top + h;
    final left = cx - w / 2;
    final right = cx + w / 2;

    return Path()
      // Start at crown centre
      ..moveTo(cx, top)
      // Crown → right temple
      ..cubicTo(
        cx + w * 0.38, top,
        right, top + h * 0.18,
        right, top + h * 0.42,
      )
      // Right cheek → right jaw → chin
      ..cubicTo(
        right, top + h * 0.70,
        cx + w * 0.28, bottom - h * 0.04,
        cx, bottom,
      )
      // Chin → left jaw → left cheek
      ..cubicTo(
        cx - w * 0.28, bottom - h * 0.04,
        left, top + h * 0.70,
        left, top + h * 0.42,
      )
      // Left temple → crown
      ..cubicTo(
        left, top + h * 0.18,
        cx - w * 0.38, top,
        cx, top,
      )
      ..close();
  }

  void _drawEyeGuides(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final w = size.width * 0.58;
    final h = size.height * 0.52;
    final top = size.height * 0.10;

    final eyeY = top + h * 0.38;
    final eyeSpacing = w * 0.20;

    final dotPaint = Paint()
      ..color = Colors.white30
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(cx - eyeSpacing, eyeY), 4, dotPaint);
    canvas.drawCircle(Offset(cx + eyeSpacing, eyeY), 4, dotPaint);
  }

  @override
  bool shouldRepaint(_HeadSilhouettePainter old) =>
      old.faceDetected != faceDetected;
}

// ---------------------------------------------------------------------------
// Countdown ring shown in top-right when face is held steady
// ---------------------------------------------------------------------------

class _CountdownIndicator extends StatefulWidget {
  const _CountdownIndicator({
    required this.startedAt,
    required this.duration,
  });

  final DateTime startedAt;
  final Duration duration;

  @override
  State<_CountdownIndicator> createState() => _CountdownIndicatorState();
}

class _CountdownIndicatorState extends State<_CountdownIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    final elapsed = DateTime.now().difference(widget.startedAt);
    final remaining = widget.duration - elapsed;

    _ctrl = AnimationController(
      vsync: this,
      duration: remaining > Duration.zero ? remaining : Duration.zero,
      value: elapsed.inMilliseconds / widget.duration.inMilliseconds,
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => SizedBox.square(
        dimension: 40,
        child: CircularProgressIndicator(
          value: _ctrl.value,
          strokeWidth: 3,
          color: Colors.greenAccent,
          backgroundColor: Colors.white24,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom panel
// ---------------------------------------------------------------------------

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.faceDetected,
    required this.capturing,
    required this.onCapture,
  });

  final bool faceDetected;
  final bool capturing;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            capturing
                ? 'Processing...'
                : faceDetected
                    ? 'Hold still — capturing automatically'
                    : 'Position your face inside the outline',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: faceDetected ? Colors.greenAccent : Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          // Manual shutter button
          GestureDetector(
            onTap: capturing ? null : onCapture,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: capturing ? Colors.grey.shade600 : Colors.white,
                border: Border.all(
                  color: faceDetected ? Colors.greenAccent : Colors.white54,
                  width: 3,
                ),
              ),
              child: capturing
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.black87,
                      size: 30,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen camera preview helper
// ---------------------------------------------------------------------------

class _CameraPreviewFill extends StatelessWidget {
  const _CameraPreviewFill({
    required this.controller,
    required this.screenSize,
  });

  final CameraController controller;
  final Size screenSize;

  @override
  Widget build(BuildContext context) {
    return OverflowBox(
      maxWidth: screenSize.width,
      maxHeight: screenSize.height,
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: CameraPreview(controller),
      ),
    );
  }
}
