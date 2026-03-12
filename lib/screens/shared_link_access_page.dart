import 'package:flutter/material.dart';

import '../controllers/scanner_controller.dart';
import '../models/report_details.dart';

class SharedLinkAccessPage extends StatefulWidget {
  const SharedLinkAccessPage({super.key, required this.controller});

  final ScannerController controller;

  @override
  State<SharedLinkAccessPage> createState() => _SharedLinkAccessPageState();
}

class _SharedLinkAccessPageState extends State<SharedLinkAccessPage> {
  final _linkController = TextEditingController();
  final _mobileController = TextEditingController();
  final _otpController = TextEditingController();
  ReportDetails? _report;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _linkController.dispose();
    _mobileController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final linkText = _linkController.text.trim();
    final mobile = _mobileController.text.trim();
    final otp = _otpController.text.trim();
    final shareId = _extractShareId(linkText);

    if (shareId == null || shareId.isEmpty) {
      setState(() => _error = 'Enter a valid share link or ID.');
      return;
    }
    if (mobile.isEmpty || otp.isEmpty) {
      setState(() => _error = 'Enter mobile number and OTP.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _report = null;
    });

    try {
      final report = await widget.controller.verifyShareOtp(
        shareId: shareId,
        mobileNumber: mobile,
        otp: otp,
      );
      setState(() => _report = report);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Shared Report'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _linkController,
              decoration: const InputDecoration(
                labelText: 'Share link or ID',
                hintText: 'Paste the share link here',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'OTP',
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _verify,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Verify & View'),
            ),
            const SizedBox(height: 16),
            if (_report != null) _ReportSummary(report: _report!),
          ],
        ),
      ),
    );
  }

  String? _extractShareId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains('/')) {
      final parts = trimmed.split('/').where((p) => p.trim().isNotEmpty).toList();
      return parts.isEmpty ? null : parts.last;
    }
    return trimmed;
  }
}

class _ReportSummary extends StatelessWidget {
  const _ReportSummary({required this.report});

  final ReportDetails report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report ID: ${report.reportId}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              'Risk: ${report.riskLevel ?? 'Unknown'}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              report.summary ?? 'No summary available.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
