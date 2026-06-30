import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionConsentDialog extends StatefulWidget {
  const PermissionConsentDialog({super.key, required this.onGranted});

  final VoidCallback onGranted;

  /// Shows the consent dialog. Calls [onGranted] if all permissions are granted.
  static Future<void> show(BuildContext context, VoidCallback onGranted) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PermissionConsentDialog(onGranted: onGranted),
    );
  }

  @override
  State<PermissionConsentDialog> createState() =>
      _PermissionConsentDialogState();
}

class _PermissionConsentDialogState extends State<PermissionConsentDialog> {
  bool _requesting = false;
  String? _errorMessage;

  Future<void> _requestPermissions() async {
    setState(() {
      _requesting = true;
      _errorMessage = null;
    });

    final statuses = await [
      Permission.location,
      Permission.camera,
    ].request();

    if (!mounted) return;

    final locationStatus = statuses[Permission.location]!;
    final cameraStatus = statuses[Permission.camera]!;

    if (locationStatus.isGranted && cameraStatus.isGranted) {
      Navigator.of(context).pop();
      widget.onGranted();
      return;
    }

    final isPermanentlyDenied =
        locationStatus.isPermanentlyDenied || cameraStatus.isPermanentlyDenied;

    setState(() {
      _requesting = false;
      _errorMessage = isPermanentlyDenied
          ? 'Permission permanently denied. Open Settings to enable it.'
          : 'Both location and camera access are required to check in.';
    });

    if (isPermanentlyDenied) openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Permissions Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This app needs the following permissions to verify your attendance:',
          ),
          const SizedBox(height: 20),
          const _PermissionItem(
            icon: Icons.location_on,
            title: 'Location',
            description:
                'Confirms you are within the allowed office radius before check-in.',
          ),
          const SizedBox(height: 16),
          const _PermissionItem(
            icon: Icons.camera_alt,
            title: 'Camera',
            description:
                'Used for the liveness check and face verification steps.',
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _requesting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _requesting ? null : _requestPermissions,
          child: _requesting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Grant Access'),
        ),
      ],
    );
  }
}

class _PermissionItem extends StatelessWidget {
  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
