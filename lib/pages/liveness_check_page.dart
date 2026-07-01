import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// ---------------------------------------------------------------------------
// Liveness challenge definitions
// ---------------------------------------------------------------------------

enum LivenessChallenge { blink, turnLeft, turnRight }

extension _ChallengeExt on LivenessChallenge {
  String get instruction => switch (this) {
        LivenessChallenge.blink => 'Blink your eyes',
        LivenessChallenge.turnLeft => 'Turn your head LEFT',
        LivenessChallenge.turnRight => 'Turn your head RIGHT',
      };

  IconData get icon => switch (this) {
        LivenessChallenge.blink => Icons.visibility_off_outlined,
        LivenessChallenge.turnLeft => Icons.arrow_back_rounded,
        LivenessChallenge.turnRight => Icons.arrow_forward_rounded,
      };
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Liveness detection screen.
///
/// Runs two sequential challenges (blink + random head-turn) using the front
/// camera and Google MLKit. Pops with [true] on success, [false] on failure,
/// and [null] if the user cancels.
///
/// Designed to be pushed before [DetectionView] so face verification only
/// runs after liveness is confirmed.
class LivenessCheckPage extends StatefulWidget {
  const LivenessCheckPage({
    super.key,
    required this.cameraDescription,
    this.blinkThreshold = 0.2,
    this.eyeOpenThreshold = 0.7,
    this.headTurnAngle = 20.0,
    this.frameSkipCount = 6,
    this.challengeTimeoutSeconds = 15,
  });

  final CameraDescription cameraDescription;

  /// Eye open probability below which a blink is counted (0 = fully closed).
  final double blinkThreshold;

  /// Eye open probability above which eyes are considered open (before blink check).
  final double eyeOpenThreshold;

  /// Absolute headEulerAngleY degrees required to pass a head-turn challenge.
  final double headTurnAngle;

  /// Process every N-th camera frame to reduce CPU usage.
  final int frameSkipCount;

  /// Seconds allowed per challenge before the page pops with false.
  final int challengeTimeoutSeconds;

  @override
  State<LivenessCheckPage> createState() => _LivenessCheckPageState();
}

class _LivenessCheckPageState extends State<LivenessCheckPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Camera & detector
  // ---------------------------------------------------------------------------

  CameraController? _camera;
  late final FaceDetector _detector;

  bool _isBusy = false;
  int _frameCount = 0;
  bool _faceDetected = false;

  // ---------------------------------------------------------------------------
  // Challenge state
  // ---------------------------------------------------------------------------

  late final List<LivenessChallenge> _challenges;
  int _currentIndex = 0;
  bool _challengeComplete = false;

  // Blink sub-state: we need eyes-open before we count eyes-closed as a blink.
  bool _eyesWereOpen = false;

  // Per-challenge timeout
  DateTime? _challengeStart;

  // ---------------------------------------------------------------------------
  // Animation (success flash)
  // ---------------------------------------------------------------------------

  late final AnimationController _flashCtrl;
  late final Animation<double> _flashOpacity;

  // ---------------------------------------------------------------------------
  // Orientations for rotation compensation (mirrors FaceDetectorService logic)
  // ---------------------------------------------------------------------------

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

    // Randomly pick: blink first, then left or right
    final turnChallenge =
        Random().nextBool() ? LivenessChallenge.turnLeft : LivenessChallenge.turnRight;
    _challenges = [LivenessChallenge.blink, turnChallenge];

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flashOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flashCtrl, curve: Curves.easeInOut),
    );

    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // eye open probabilities
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose(); // no-op if already released via _releaseCamera
    _camera = null;
    _detector.close();
    _flashCtrl.dispose();
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
  // Camera init
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
    _challengeStart = DateTime.now();
    setState(() {});

    cam.startImageStream(_onFrame);
  }

  // ---------------------------------------------------------------------------
  // Frame processing
  // ---------------------------------------------------------------------------

  Future<void> _onFrame(CameraImage image) async {
    _frameCount++;
    if (_frameCount % widget.frameSkipCount != 0) return;
    if (_isBusy || _challengeComplete) return;

    _isBusy = true;
    try {
      // Timeout check
      final elapsed = DateTime.now()
          .difference(_challengeStart ?? DateTime.now())
          .inSeconds;
      if (elapsed >= widget.challengeTimeoutSeconds) {
        await _releaseCamera();
        if (mounted) Navigator.of(context).pop(false);
        return;
      }

      final inputImage = _toInputImage(image);
      if (inputImage == null) return;

      final faces = await _detector.processImage(inputImage);

      final hasFace = faces.isNotEmpty;
      if (hasFace != _faceDetected) {
        if (mounted) setState(() => _faceDetected = hasFace);
      }

      if (hasFace) {
        _evaluate(faces.first);
      }
    } finally {
      _isBusy = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Challenge evaluation
  // ---------------------------------------------------------------------------

  void _evaluate(Face face) {
    final challenge = _challenges[_currentIndex];

    switch (challenge) {
      case LivenessChallenge.blink:
        final leftOpen = face.leftEyeOpenProbability ?? 1.0;
        final rightOpen = face.rightEyeOpenProbability ?? 1.0;

        // Phase A: confirm eyes are open first
        if (leftOpen > widget.eyeOpenThreshold &&
            rightOpen > widget.eyeOpenThreshold) {
          _eyesWereOpen = true;
        }
        // Phase B: now detect the blink
        if (_eyesWereOpen &&
            leftOpen < widget.blinkThreshold &&
            rightOpen < widget.blinkThreshold) {
          _passChallenge();
        }

      case LivenessChallenge.turnLeft:
        // Positive eulerAngleY = face looking left (user's perspective, front cam)
        if ((face.headEulerAngleY ?? 0).abs() >= widget.headTurnAngle &&
            (face.headEulerAngleY ?? 0) > 0) {
          _passChallenge();
        }

      case LivenessChallenge.turnRight:
        // Negative eulerAngleY = face looking right (user's perspective, front cam)
        if ((face.headEulerAngleY ?? 0).abs() >= widget.headTurnAngle &&
            (face.headEulerAngleY ?? 0) < 0) {
          _passChallenge();
        }
    }
  }

  Future<void> _releaseCamera() async {
    final cam = _camera;
    if (cam == null) return;
    _camera = null;
    if (cam.value.isStreamingImages) await cam.stopImageStream();
    await cam.dispose();
  }

  Future<void> _passChallenge() async {
    _challengeComplete = true;

    // Green flash animation
    await _flashCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    await _flashCtrl.reverse();

    final isLast = _currentIndex >= _challenges.length - 1;

    if (isLast) {
      // Release hardware before the next page opens the same camera
      await _releaseCamera();
      if (mounted) Navigator.of(context).pop(true);
    } else {
      // Move to next challenge
      if (mounted) {
        setState(() {
          _currentIndex++;
          _challengeComplete = false;
          _eyesWereOpen = false;
          _challengeStart = DateTime.now();
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // InputImage conversion (mirrors FaceDetectorService._inputImageFromCameraImage)
  // ---------------------------------------------------------------------------

  InputImage? _toInputImage(CameraImage image) {
    final sensorOrientation = widget.cameraDescription.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      final deviceRot =
          _orientations[_camera?.value.deviceOrientation] ?? 0;
      // Front camera rotation compensation
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
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    final initialized = cam != null && cam.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: initialized ? _buildCamera(cam) : _buildLoading(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _buildCamera(CameraController cam) {
    final challenge = _challenges[_currentIndex];

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-screen camera preview
        _FullScreenCameraPreview(controller: cam),

        // Success flash overlay
        AnimatedBuilder(
          animation: _flashOpacity,
          builder: (_, _) => Opacity(
            opacity: _flashOpacity.value * 0.4,
            child: const ColoredBox(color: Colors.green),
          ),
        ),

        // Face oval guide
        _FaceOvalGuide(faceDetected: _faceDetected),

        // Top bar: cancel + progress
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black38,
                  ),
                ),
                _ChallengeProgress(
                  total: _challenges.length,
                  completed: _currentIndex,
                ),
              ],
            ),
          ),
        ),

        // Bottom instruction panel
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: _InstructionPanel(
              challenge: challenge,
              faceDetected: _faceDetected,
              timeoutSeconds: widget.challengeTimeoutSeconds,
              challengeStart: _challengeStart ?? DateTime.now(),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _FullScreenCameraPreview extends StatelessWidget {
  const _FullScreenCameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const SizedBox.expand();

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _FaceOvalGuide extends StatelessWidget {
  const _FaceOvalGuide({required this.faceDetected});
  final bool faceDetected;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OvalOverlayPainter(faceDetected: faceDetected),
    );
  }
}

class _OvalOverlayPainter extends CustomPainter {
  const _OvalOverlayPainter({required this.faceDetected});
  final bool faceDetected;

  @override
  void paint(Canvas canvas, Size size) {
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.62,
      height: size.height * 0.42,
    );

    // Dim everything outside the oval
    final dimPaint = Paint()..color = Colors.black54;
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dimPaint);

    // Oval border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = faceDetected ? Colors.greenAccent : Colors.white60;
    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(_OvalOverlayPainter old) =>
      old.faceDetected != faceDetected;
}

class _ChallengeProgress extends StatelessWidget {
  const _ChallengeProgress({required this.total, required this.completed});
  final int total;
  final int completed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final done = i < completed;
        final current = i == completed;
        return Container(
          margin: const EdgeInsets.only(left: 6),
          width: current ? 24 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: done
                ? Colors.greenAccent
                : current
                    ? Colors.white
                    : Colors.white38,
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }
}

class _InstructionPanel extends StatefulWidget {
  const _InstructionPanel({
    required this.challenge,
    required this.faceDetected,
    required this.timeoutSeconds,
    required this.challengeStart,
  });

  final LivenessChallenge challenge;
  final bool faceDetected;
  final int timeoutSeconds;
  final DateTime challengeStart;

  @override
  State<_InstructionPanel> createState() => _InstructionPanelState();
}

class _InstructionPanelState extends State<_InstructionPanel> {
  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.challengeStart).inSeconds;
    final remaining = (widget.timeoutSeconds - elapsed).clamp(0, widget.timeoutSeconds);
    final progress = remaining / widget.timeoutSeconds;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.faceDetected)
            Text(
              'Position your face in the oval',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            )
          else ...[
            Icon(widget.challenge.icon, color: Colors.white, size: 32),
            const SizedBox(height: 10),
            Text(
              widget.challenge.instruction,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.toDouble(),
              minHeight: 5,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(
                progress > 0.4 ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
