import 'package:flutter/material.dart';
import '../models/checkin_result.dart';

/// Home page shown after a successful check-in.
///
/// Receives an immutable [CheckinResult] — no controller needed here.
/// Replace the contents with your actual home screen once the POC is verified.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.result});

  final CheckinResult result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check In Success'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SuccessBadge(),
              const SizedBox(height: 32),
              _InfoCard(result: result),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_rounded,
            size: 64,
            color: Colors.green.shade600,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Attendance Recorded',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your check-in has been saved successfully.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.result});
  final CheckinResult result;

  @override
  Widget build(BuildContext context) {
    final time = result.checkinTime;
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final dateStr =
        '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _InfoRow(
              icon: Icons.person_outline,
              label: 'Employee',
              value: result.employeeName,
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.access_time_outlined,
              label: 'Time',
              value: '$timeStr  ·  $dateStr',
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Coordinates',
              value:
                  '${result.lat.toStringAsFixed(6)}, ${result.lng.toStringAsFixed(6)}',
            ),
            const Divider(height: 24),
            _InfoRow(
              icon: Icons.radar_outlined,
              label: 'Distance',
              value:
                  '${result.distanceMeters.toStringAsFixed(0)} m  '
                  '(max ${result.officeRadiusMeters.toStringAsFixed(0)} m)',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade500),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
