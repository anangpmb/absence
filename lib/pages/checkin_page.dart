import 'package:flutter/material.dart';

import '../controllers/checkin_controller.dart';
import '../models/employee_model.dart';
import 'face_capture_page.dart';
import 'home_page.dart';
import 'liveness_check_page.dart';

/// Check-in page.
///
/// Receives [controller] and [employee] via constructor — works with any
/// DI/state-management setup (Provider, Riverpod, GetX, Bloc, etc.).
/// All business logic lives in the controller; this page owns only
/// navigation and UI rendering.
class CheckinPage extends StatefulWidget {
  const CheckinPage({
    super.key,
    required this.controller,
    required this.employee,
  });

  final CheckinController controller;
  final EmployeeModel employee;

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // React to controller state changes
  // ---------------------------------------------------------------------------

  void _onControllerUpdate() {
    if (!mounted) return;

    switch (widget.controller.status) {
      case CheckinStatus.awaitingLiveness:
        _openLivenessCheck();
      case CheckinStatus.awaitingVerification:
        _openFaceCapture();
      case CheckinStatus.success:
        _navigateToHome();
      default:
        setState(() {});
    }
  }

  Future<void> _openLivenessCheck() async {
    final camera = widget.controller.pendingCamera;
    if (camera == null) return;

    // true = passed, false = timed out, null = user cancelled
    final passed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LivenessCheckPage(cameraDescription: camera),
      ),
    );

    if (mounted) widget.controller.completeLiveness(passed);
  }

  Future<void> _openFaceCapture() async {
    final camera = widget.controller.pendingCamera;
    if (camera == null) return;

    // Returns the captured photo file path, or null on cancel
    final photoPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceCapturePage(cameraDescription: camera),
      ),
    );

    if (mounted) await widget.controller.completeCapture(photoPath);
  }

  void _navigateToHome() {
    final result = widget.controller.result;
    if (result == null) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage(result: result)),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isLoading = _isLoadingStatus(controller.status);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Check In'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EmployeeCard(employee: widget.employee),
              const SizedBox(height: 40),
              _StatusIcon(status: controller.status),
              const SizedBox(height: 20),
              Text(
                controller.statusMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (controller.errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: controller.errorMessage!),
              ],
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: isLoading
                    ? null
                    : () => widget.controller.startCheckin(widget.employee),
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.face_retouching_natural),
                label: Text(
                  controller.status == CheckinStatus.failed
                      ? 'Try Again'
                      : 'Start Check In',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isLoadingStatus(CheckinStatus s) =>
      s != CheckinStatus.idle && s != CheckinStatus.failed;
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee});
  final EmployeeModel employee;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: NetworkImage(employee.referencePhotoUrl),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${employee.id}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});
  final CheckinStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      CheckinStatus.failed => const Icon(
          Icons.error_outline,
          size: 80,
          color: Colors.red,
        ),
      CheckinStatus.idle => const Icon(
          Icons.fingerprint,
          size: 80,
          color: Colors.blue,
        ),
      _ => const SizedBox.square(
          dimension: 80,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
    };
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.red.shade700),
      ),
    );
  }
}
