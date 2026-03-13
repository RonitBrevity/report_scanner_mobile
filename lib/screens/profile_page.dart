import 'package:flutter/material.dart';

import '../controllers/scanner_controller.dart';
import '../models/patient.dart';
import 'add_patient_page.dart';
import 'edit_patient_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.controller});

  final ScannerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final selected = controller.selectedPatient;
        final patientCount = controller.patients.length;
        final reportCount = controller.pastReports.length + (controller.report == null ? 0 : 1);
        return Stack(
          children: [
            Scaffold(
              backgroundColor: const Color(0xFFF0FDFA),
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0.5,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black87),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: const Text('Doctor Profile'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.settings),
                    color: Colors.black87,
                    onPressed: () {},
                  )
                ],
              ),
              body: SafeArea(
                child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Center(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0F766E), Color(0xFF2DD4BF)],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: CircleAvatar(
                              radius: 52,
                              backgroundColor: Colors.white,
                              child: Text(
                                _initials(selected?.name ?? 'User'),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            right: 4,
                            child: Material(
                              color: const Color(0xFF0F766E),
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: () {},
                                customBorder: const CircleBorder(),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.edit, color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Dr. HealthScan',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Consultant • Internal Medicine',
                        style: TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _StatCard(label: 'Patients', value: '$patientCount'),
                    const SizedBox(width: 12),
                    _StatCard(label: 'Reports', value: '$reportCount'),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Account Information',
                  style: theme.textTheme.labelLarge?.copyWith(
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                _InfoCard(icon: Icons.badge_outlined, title: 'Doctor Name', value: 'Dr. HealthScan'),
                _InfoCard(icon: Icons.location_city, title: 'Clinic', value: 'HealthScan AI Center'),
                _InfoCard(icon: Icons.call, title: 'Contact', value: '+91 98765 43210'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Linked Patients',
                      style: theme.textTheme.labelLarge?.copyWith(
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final created = await Navigator.of(context).push<Patient>(
                          MaterialPageRoute(
                            builder: (_) => AddPatientPage(controller: controller),
                          ),
                        );
                        if (created != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Patient ${created.name} added')),
                          );
                        }
                      },
                      child: const Text('+ ADD NEW'),
                    ),
                  ],
                ),
                ...controller.patients.map(
                  (p) => _LinkedPatientTile(
                    patient: p,
                    isSelected: p.patientId == controller.selectedPatient?.patientId,
                    onTap: () => _showPatientDetails(context, p),
                    onEdit: () async {
                      final updated = await Navigator.of(context).push<Patient?>(
                        MaterialPageRoute(
                          builder: (_) => EditPatientPage(controller: controller, patient: p),
                        ),
                      );
                      if (updated != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Patient ${updated.name} updated')),
                        );
                      }
                    },
                    onDelete: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Delete patient?'),
                          content: Text(
                            'Delete ${p.name} (Code: ${p.patientCode}) and all related reports?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dialogContext).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(dialogContext).pop(true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      try {
                        await controller.deletePatient(p.patientId);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Patient ${p.name} deleted')),
                        );
                      } catch (_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(controller.error ?? 'Failed to delete patient.')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _ActionTile(
                  icon: Icons.verified_user_outlined,
                  label: 'Privacy & Security',
                  onTap: () {},
                ),
                _ActionTile(
                  icon: Icons.logout,
                  label: 'Logout',
                  accentColor: Colors.red.shade600,
                  onTap: () {},
                ),
              ],
            ),
              ),
            ),
            if (controller.isSubmitting || controller.isLoadingPatients)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.15),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.6),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  void _showPatientDetails(BuildContext context, Patient patient) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final selected = controller.selectedPatient?.patientId == patient.patientId;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFF99F6E4),
                        child: Text(
                          patient.name.isNotEmpty ? patient.name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Color(0xFF0F766E),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patient.name,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Code: ${patient.patientCode}',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Current',
                            style: TextStyle(
                              color: Color(0xFF0F766E),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoPill(label: 'Age', value: '${patient.age} yrs'),
                      _InfoPill(label: 'Gender', value: patient.gender),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            controller.setSelectedPatient(patient);
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Switched to ${patient.name}')),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF0F766E)),
                            foregroundColor: const Color(0xFF0F766E),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Set as Current'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD1E7E4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD1E7E4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0F766E)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class _LinkedPatientTile extends StatelessWidget {
  const _LinkedPatientTile({
    required this.patient,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Patient patient;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F766E) : const Color(0xFFD1E7E4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF99F6E4),
              child: Text(
                patient.name.isNotEmpty ? patient.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Color(0xFF0F766E),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Code: ${patient.patientCode}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onEdit,
                  tooltip: 'Edit',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF0F766E)),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade600),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Colors.black87;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: accentColor == null ? Colors.white : color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD1E7E4)),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F2F1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: Color(0xFF0F766E),
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
