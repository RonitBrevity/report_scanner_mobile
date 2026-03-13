import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_saver/file_saver.dart';

import '../controllers/scanner_controller.dart';
import '../models/patient.dart';
import '../models/report_details.dart';
import '../models/selected_upload_file.dart';
import '../services/api_client.dart';
import 'profile_page.dart';
import 'shared_link_access_page.dart';

enum _DateFilter { newestFirst, oldestFirst }

enum _TypeFilter { all, highRisk, review, normal }

enum _RangeFilter { all, last7, last30, last90, last180, last365 }

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key, required this.controller});

  final ScannerController controller;

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _patientSearchController = TextEditingController();
  BuildContext? _tabControllerContext;
  _DateFilter _dateFilter = _DateFilter.newestFirst;
  _TypeFilter _typeFilter = _TypeFilter.all;
  _RangeFilter _rangeFilter = _RangeFilter.all;
  bool _abnormalOnly = false;
  String _testTypeFilter = 'All';
  String _patientSearchQuery = '';

  @override
  void initState() {
    super.initState();
    widget.controller.loadPatients();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _patientSearchController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 180) {
      widget.controller.loadNextPastReport();
    }
  }

  Future<void> _pickCameraImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (image == null) {
      return;
    }

    final currentImages = widget.controller.selectedImages;
    if (currentImages.length >= 4) {
      _showMessage('You can upload a maximum of 4 images.');
      return;
    }

    widget.controller.setSelectedImages(<XFile>[...currentImages, image]);
    _goToReportsTab();
    _scrollToTop();
  }

  Future<void> _pickGalleryImages() async {
    final images = await _picker.pickMultiImage(
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (images.isEmpty) {
      return;
    }

    if (images.length > 4) {
      _showMessage('Only the first 4 images were added.');
    }

    widget.controller.setSelectedImages(images.take(4).toList());
    _goToReportsTab();
    _scrollToTop();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    final path = file.path;
    if (path == null) {
      _showMessage('Selected PDF path is not available.');
      return;
    }

    widget.controller.setSelectedPdf(
      SelectedUploadFile(name: file.name, path: path, extension: 'pdf'),
    );
    _goToReportsTab();
    _scrollToTop();
  }

  Future<void> _exportCurrentReport() async {
    try {
      final path = await widget.controller.exportCurrentReportPdf();
      final savedPath = await _savePdfToDevice(path, 'healthscan_current_report');
      _showMessage(savedPath == null
          ? 'Download canceled.'
          : 'Current report saved to $savedPath');
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _exportPastReport(ReportDetails report) async {
    try {
      final path = await widget.controller.exportPastReportPdf(report);
      final savedPath = await _savePdfToDevice(path, 'healthscan_${report.reportId}');
      _showMessage(savedPath == null
          ? 'Download canceled.'
          : 'Past report saved to $savedPath');
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<String?> _savePdfToDevice(String path, String baseName) async {
    final bytes = await File(path).readAsBytes();
    return FileSaver.instance.saveFile(
      name: baseName,
      bytes: bytes,
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<void> _confirmDeleteReport(ReportDetails report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Report?'),
        content: const Text(
          'This will permanently remove this laboratory report and its historical data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await widget.controller.deleteReport(report.reportId);
      if (success) {
        _showMessage('Report deleted successfully.');
      } else {
        _showMessage(widget.controller.error ?? 'Failed to delete report.');
      }
    }
  }

  Future<void> _showShareReportSheet(ReportDetails report) async {
    final mobileController = TextEditingController();
    String expiryOption = '1m';
    String? shareUrl;
    String? shareId;
    String? statusMessage;
    String? errorMessage;
    bool isLoading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        var sheetOpen = true;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> handleShare() async {
              if (!sheetOpen) return;
              final mobile = mobileController.text.trim();
              if (mobile.isEmpty) {
                setModalState(() {
                  errorMessage = 'Enter a mobile number to receive the OTP.';
                });
                return;
              }

              setModalState(() {
                isLoading = true;
                errorMessage = null;
                statusMessage = null;
              });

              try {
                if (shareId == null) {
                  final sharePath = await widget.controller.createShareLink(
                    reportId: report.reportId,
                    targetMobileNumber: mobile,
                    expiryOption: expiryOption,
                  );
                  final resolvedUrl = _buildShareUrl(
                    widget.controller.baseUrl,
                    sharePath,
                  );
                  shareUrl = resolvedUrl;
                  shareId = _extractShareId(sharePath) ?? _extractShareId(resolvedUrl);
                }

                if (shareId == null || shareId!.isEmpty) {
                  throw Exception('Share link ID was missing.');
                }

                await widget.controller.requestShareOtp(
                  shareId: shareId!,
                  mobileNumber: mobile,
                );

                if (sheetOpen) {
                  setModalState(() {
                    statusMessage = 'OTP sent to $mobile';
                  });
                }
              } on ApiException catch (e) {
                if (sheetOpen) {
                  setModalState(() {
                    errorMessage = e.message;
                  });
                }
              } catch (_) {
                if (sheetOpen) {
                  setModalState(() {
                    errorMessage = 'Failed to send OTP.';
                  });
                }
              } finally {
                if (sheetOpen) {
                  setModalState(() {
                    isLoading = false;
                  });
                }
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Share report',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          sheetOpen = false;
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Generate a secure link and send an OTP to the recipient.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.blueGrey.shade600,
                        ),
                  ),
                  const SizedBox(height: 16),
              TextField(
                controller: mobileController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Recipient mobile number',
                      prefixIcon: const Icon(Icons.phone_android),
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                ),
                onChanged: (_) => setModalState(() {}),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: expiryOption,
                decoration: InputDecoration(
                  labelText: 'Link expiry',
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: '1d', child: Text('1 Day')),
                  DropdownMenuItem(value: '1m', child: Text('1 Month')),
                  DropdownMenuItem(value: '3m', child: Text('3 Months')),
                  DropdownMenuItem(value: '6m', child: Text('6 Months')),
                ],
                onChanged: (value) => setModalState(() => expiryOption = value ?? '1m'),
              ),
              const SizedBox(height: 12),
              if (errorMessage != null)
                Text(
                  errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  if (statusMessage != null)
                    Text(
                      statusMessage!,
                      style: const TextStyle(color: Color(0xFF0B6F66), fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : handleShare,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(shareId == null ? 'Generate Link & Send OTP' : 'Resend OTP'),
                    ),
                  ),
                  if (shareUrl != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Share link',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      shareUrl!,
                      style: const TextStyle(color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: shareUrl!));
                          _showMessage('Share link copied to clipboard.');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy link'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );

    mobileController.dispose();
  }

  String _buildShareUrl(String baseUrl, String sharePath) {
    if (sharePath.startsWith('http://') || sharePath.startsWith('https://')) {
      return sharePath;
    }
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = sharePath.startsWith('/') ? sharePath : '/$sharePath';
    return '$normalizedBase$normalizedPath';
  }

  String? _extractShareId(String shareUrl) {
    final uri = Uri.tryParse(shareUrl);
    final segments = uri?.pathSegments ??
        shareUrl.split('/').where((segment) => segment.trim().isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return segments.last;
  }

  void _showDateFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Newest first'),
              trailing: _dateFilter == _DateFilter.newestFirst
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                setState(() => _dateFilter = _DateFilter.newestFirst);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Oldest first'),
              trailing: _dateFilter == _DateFilter.oldestFirst
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                setState(() => _dateFilter = _DateFilter.oldestFirst);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTypeFilterSheet() {
    final options = <(_TypeFilter, String)>[
      (_TypeFilter.all, 'All reports'),
      (_TypeFilter.highRisk, 'High risk'),
      (_TypeFilter.review, 'Review'),
      (_TypeFilter.normal, 'Normal'),
    ];

    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (entry) => ListTile(
                  title: Text(entry.$2),
                  trailing: _typeFilter == entry.$1
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setState(() => _typeFilter = entry.$1);
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _showSmartFilterSheet() {
    final options = <(_RangeFilter, String)>[
      (_RangeFilter.all, 'All time'),
      (_RangeFilter.last7, 'Last 7 days'),
      (_RangeFilter.last30, 'Last 30 days'),
      (_RangeFilter.last90, 'Last 3 months'),
      (_RangeFilter.last180, 'Last 6 months'),
      (_RangeFilter.last365, 'Last 1 year'),
    ];
    final categories = _availableReportCategories();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart filters',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 16),
                const Text('Date range', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.map((entry) {
                    final active = _rangeFilter == entry.$1;
                    return ChoiceChip(
                      label: Text(entry.$2),
                      selected: active,
                      onSelected: (_) => setState(() => _rangeFilter = entry.$1),
                      selectedColor: const Color(0xFF0F766E).withOpacity(0.15),
                      labelStyle: TextStyle(
                        color: active ? const Color(0xFF0F766E) : const Color(0xFF1F2937),
                        fontWeight: FontWeight.w700,
                      ),
                      side: const BorderSide(color: Color(0xFFD1E7E4)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Abnormal only', style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Switch(
                      value: _abnormalOnly,
                      onChanged: (value) => setState(() => _abnormalOnly = value),
                      activeColor: const Color(0xFF0F766E),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Test type', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories.map((category) {
                    final active = _testTypeFilter == category;
                    return ChoiceChip(
                      label: Text(category),
                      selected: active,
                      onSelected: (_) => setState(() => _testTypeFilter = category),
                      selectedColor: const Color(0xFF0F766E).withOpacity(0.15),
                      labelStyle: TextStyle(
                        color: active ? const Color(0xFF0F766E) : const Color(0xFF1F2937),
                        fontWeight: FontWeight.w700,
                      ),
                      side: const BorderSide(color: Color(0xFFD1E7E4)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _rangeFilter = _RangeFilter.all;
                        _abnormalOnly = false;
                        _testTypeFilter = 'All';
                      });
                    },
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _goToReportsTab() {
    final controller = _tabControllerContext == null
        ? null
        : DefaultTabController.of(_tabControllerContext!);
    if (controller != null && controller.index != 0) {
      controller.animateTo(0);
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (_, __) {
        final controller = widget.controller;
        final report = controller.report;
        final pastReports = _applyFilters(controller.pastReports);

        return DefaultTabController(
          length: 2,
          child: Builder(
            builder: (tabContext) {
              _tabControllerContext = tabContext;
              return Scaffold(
            backgroundColor: const Color(0xFFF8FBFB),
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: Text(
                'HealthScan AI',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F766E),
                ),
              ),
              actions: [
                IconButton(
                  onPressed: controller.loadPatients,
                  icon: const Icon(Icons.refresh_rounded),
                  color: const Color(0xFF0B6F66),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SharedLinkAccessPage(controller: controller),
                    ),
                  ),
                  icon: const Icon(Icons.link_outlined),
                  color: const Color(0xFF0B6F66),
                  tooltip: 'Open shared link',
                ),
              ],
              bottom: TabBar(
                indicatorColor: const Color(0xFF0F766E),
                indicatorWeight: 3,
                labelColor: const Color(0xFF0F766E),
                unselectedLabelColor: Colors.blueGrey.shade400,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                tabs: const [
                  Tab(text: 'Reports'),
                  Tab(text: 'Analysis'),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: controller.isBusy
                  ? null
                  : () {
                      if (controller.selectedPatient == null) {
                        _showMessage('Select a patient before uploading a report.');
                        return;
                      }
                      _showUploadOptions(controller);
                    },
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              child: const Icon(Icons.document_scanner_outlined),
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
            bottomNavigationBar: BottomAppBar(
              shape: const CircularNotchedRectangle(),
              notchMargin: 8,
              color: Colors.white,
              child: SizedBox(
                height: 74,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      icon: Icons.description_outlined,
                      label: 'Reports',
                      active: true,
                      onTap: () {},
                    ),
                    const SizedBox(width: 40),
                    _NavItem(
                      icon: Icons.person_outline,
                      label: 'Profile',
                      active: false,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProfilePage(controller: controller),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            body: TabBarView(
              children: [
                _buildScanReportTab(controller, colorScheme, theme),
                _buildAnalysisTab(controller, colorScheme, theme),
              ],
            ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildScanReportTab(ScannerController controller, ColorScheme colorScheme, ThemeData theme) {
    final report = controller.report;
    final pastReports = _applyFilters(controller.pastReports);

    return Stack(
      children: [
        SafeArea(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      _PatientSelectorBar(
                        patient: controller.selectedPatient,
                        subtitle: controller.selectedPatient != null
                            ? '${controller.selectedPatient!.gender}, ${controller.selectedPatient!.age}y'
                            : 'No patient selected',
                        onTap: controller.isBusy ? null : () => _showPatientSelection(controller),
                      ),
                      const SizedBox(height: 12),
                      _buildPatientDetailsCard(controller, colorScheme, theme),
                      const SizedBox(height: 16),
                      if (controller.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            controller.error!,
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ),
                      if (report != null) ...[
                        const SizedBox(height: 24),
                        _buildReportDetailsCard(
                          report: report,
                          controller: controller,
                          theme: theme,
                          title: 'Current Report',
                          onExport: _exportCurrentReport,
                          onShare: () => _showShareReportSheet(report),
                          allowLocalPreview: true,
                        ),
                        const SizedBox(height: 24),
                      ],
                      _buildPreviousReportsSection(
                        reports: pastReports,
                        controller: controller,
                        theme: theme,
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (controller.isSubmitting)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.35),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        'Scanning and analyzing…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAnalysisTab(ScannerController controller, ColorScheme colorScheme, ThemeData theme) {
    return _AnalysisTabView(
      key: ValueKey(controller.selectedPatient?.patientId ?? 'no-patient'),
      controller: controller,
      onSelectPatient: () => _showPatientSelection(controller),
      onShareReport: (report) => _showShareReportSheet(report),
      onShowMessage: _showMessage,
    );
  }

  Widget _buildPatientCard(ScannerController controller, ColorScheme colorScheme, ThemeData theme) {
    final selectedPatient = controller.selectedPatient;
    final subtitle = selectedPatient != null
        ? '${selectedPatient.name} (ID: ${selectedPatient.patientId})'
        : 'No patient selected';

    return InkWell(
      onTap: controller.isBusy ? null : () => _showPatientSelection(controller),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD1E7E4)),
        ),
        child: Row(
          children: [
            _PatientAvatar(patient: selectedPatient, radius: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Patient',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.blueGrey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF0B6F66)),
          ],
        ),
      ),
    );
  }


  void _showPatientSelection(ScannerController controller) {
    _patientSearchController.text = '';
    _patientSearchQuery = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = _patientSearchQuery.trim().toLowerCase();
            final patients = query.isEmpty
                ? controller.patients
                : controller.patients.where((patient) {
                    final name = patient.name.toLowerCase();
                    final gender = patient.gender.toLowerCase();
                    final id = patient.patientId.toLowerCase();
                    return name.contains(query) ||
                        gender.contains(query) ||
                        id.contains(query);
                  }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Select Patient',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: TextField(
                          controller: _patientSearchController,
                          onChanged: (value) => setModalState(
                            () => _patientSearchQuery = value,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search by name, gender, or ID',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: patients.length,
                          itemBuilder: (context, index) {
                            final patient = patients[index];
                            final isSelected =
                                controller.selectedPatient?.patientId ==
                                patient.patientId;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 4,
                              ),
                              leading: _PatientAvatar(
                                patient: patient,
                                radius: 18,
                                highlighted: isSelected,
                              ),
                              title: Text(
                                patient.name,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              subtitle: Text(
                                '${patient.gender}, ${patient.age}y (ID: ${patient.patientId})',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: isSelected
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF0B6F66),
                                    )
                                  : null,
                              onTap: () {
                                controller.setSelectedPatient(patient);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPatientDetailsCard(
    ScannerController controller,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final patient = controller.selectedPatient;
    final latestReportDate = _latestReportDate(
      controller.report,
      controller.pastReports,
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8F7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD1E7E4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patient Details',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _PatientAvatar(patient: patient, radius: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      patient?.name ?? 'No patient selected',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _detailChip('Age', patient != null ? '${patient.age}y' : '—'),
                  _detailChip('Gender', patient?.gender ?? '—'),
                  _detailChip(
                    'Last Appointment',
                    latestReportDate != null ? _displayDate(latestReportDate) : '—',
                  ),
                  _detailChip('Doctor', '—'),
                ],
              ),
              const SizedBox(height: 16),
              if (controller.selectedPdf == null &&
                  controller.selectedImages.isEmpty)
                Text(
                  'Use the Scan button below to add a report.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                )
              else ...[
                _buildSelectedDocuments(controller, colorScheme, theme),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: controller.isBusy || !controller.hasSelectedDocuments
                        ? null
                        : controller.uploadAndAnalyze,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0B6F66),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text(
                      'Begin Analysis',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showUploadOptions(ScannerController controller) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Upload Report',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a method to add your medical report',
                style: TextStyle(color: Colors.blueGrey.shade600),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _UploadAction(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(context);
                      _pickCameraImage();
                    },
                  ),
                  _UploadAction(
                    icon: Icons.collections_outlined,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(context);
                      _pickGalleryImages();
                    },
                  ),
                  _UploadAction(
                    icon: Icons.upload_file_outlined,
                    label: 'PDF Document',
                    onTap: () {
                      Navigator.pop(context);
                      _pickPdf();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectedDocuments(
    ScannerController controller,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (controller.selectedPdf != null)
            _DocumentChip(
              icon: Icons.picture_as_pdf_outlined,
              label: controller.selectedPdf!.name,
              onDeleted: () => controller.setSelectedPdf(null),
            ),
          ...controller.selectedImages.map(
            (image) => _DocumentChip(
              icon: Icons.image_outlined,
              label: image.name,
              onDeleted: () => controller.removeSelectedImage(image),
            ),
          ),
          if (controller.selectedImages.isNotEmpty)
            Text(
              '${controller.selectedImages.length}/4 images selected',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReportDetailsCard({
    required ReportDetails report,
    required ScannerController controller,
    required ThemeData theme,
    required String title,
    required VoidCallback onExport,
    required VoidCallback onShare,
    required bool allowLocalPreview,
  }) {
    final summary = controller.buildReportSummary(report);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E0E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF5F7390),
                  fontWeight: FontWeight.w700,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0B6F66),
                  side: const BorderSide(color: Color(0xFF8FD6C9)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined, size: 16),
                label: const Text('Share'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0B6F66),
                  side: const BorderSide(color: Color(0xFF8FD6C9)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F0FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _displayDate(report.uploadDateUtc),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRiskBanner(report, theme),
          const SizedBox(height: 18),
          _sectionTitle('TOTAL SUMMARY', theme),
          const SizedBox(height: 8),
          Text(
            summary,
            maxLines: 9,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.55,
              color: const Color(0xFF23324D),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('CRITICAL FINDINGS', theme),
          const SizedBox(height: 10),
          if (report.criticalFindings.isEmpty)
            Text(
              'No critical findings detected.',
              style: theme.textTheme.bodyMedium,
            )
          else
            ...report.criticalFindings.map(
              (finding) {
                final palette = _criticalFindingColors(finding.severity);
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: palette.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(color: palette.accent, width: 3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          finding.finding,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFF1F2B3D),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        finding.severity,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: palette.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 18),
          _sectionTitle('DETAILED TEST RESULTS', theme),
          const SizedBox(height: 12),
          _buildDetailedResultsSection(report, theme),
          const SizedBox(height: 18),
          _sectionTitle('REPORT PREVIEW', theme),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 240,
              width: double.infinity,
              child: InkWell(
                onTap: () => _openReportPreview(report, controller, allowLocalPreview),
                child: report.imageUrl != null
                    ? Image.network(
                        _resolveImageUrl(report.imageUrl!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _previewFallback(),
                      )
                    : allowLocalPreview && controller.selectedImages.isNotEmpty
                    ? Image.file(
                        File(controller.selectedImages.first.path),
                        fit: BoxFit.cover,
                      )
                    : _previewFallback(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedResultsSection(ReportDetails report, ThemeData theme) {
    if (report.tests.isEmpty) {
      return Text(
        'No detailed test results extracted.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      children: report.tests.map((test) => _buildTestResultTile(test, theme)).toList(),
    );
  }

  Widget _buildTestResultTile(ReportTest test, ThemeData theme) {
    final isAbnormal = test.status.toLowerCase() != 'normal' && test.status.toLowerCase() != 'optimal';
    final accentColor = isAbnormal ? Colors.redAccent : const Color(0xFF0F766E);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  test.testName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  test.status.toUpperCase(),
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final unit = widget.controller.availableTests.contains(test.testName)
                  ? widget.controller.getHistoryForTest(test.testName).last.unit
                  : '';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 4,
                    children: [
                      Text(
                        '${test.value}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      if (unit.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            unit,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Range: ${_formatRangeValue(test.rangeMin)} - ${_formatRangeValue(test.rangeMax)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _buildRangeIndicator(test, accentColor),
        ],
      ),
    );
  }

  Widget _buildRangeIndicator(ReportTest test, Color accentColor) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final rMin = test.rangeMin;
            final rMax = test.rangeMax;

            double position;
            if (rMin == null || rMax == null || rMax <= rMin) {
              position = 0.5; // Center if no range
            } else {
              final range = rMax - rMin;
              position = (test.value - rMin) / range;
              // Clamp to show on bar even if out of range.
              position = (position * 0.6 + 0.2).clamp(0.05, 0.95);
            }

            return Stack(
              children: [
                Container(
                  height: 6,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                // Normal range highlight (simplified, middle 60%).
                Positioned(
                  left: 40, // Offset for normal range start.
                  right: 40, // Offset for normal range end.
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2DD4BF).withOpacity(0.3),
                    ),
                  ),
                ),
                // Bullet for current value.
                Positioned(
                  left: constraints.maxWidth * position - 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(0.3),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showPastReportDetails(ReportDetails report, ScannerController controller) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8FBFB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          top: false,
          child: DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.6,
            maxChildSize: 0.97,
            expand: false,
            builder: (context, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: _buildReportDetailsCard(
                  report: report,
                  controller: controller,
                  theme: theme,
                  title: 'Report Details',
                  onExport: () => _exportPastReport(report),
                  onShare: () => _showShareReportSheet(report),
                  allowLocalPreview: false,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPreviousReportsSection({
    required List<ReportDetails> reports,
    required ScannerController controller,
    required ThemeData theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Previous Reports',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CompactFilterButton(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  onTap: _showDateFilterSheet,
                ),
                const SizedBox(width: 6),
                _CompactFilterButton(
                  icon: Icons.filter_list_rounded,
                  label: 'Type',
                  onTap: _showTypeFilterSheet,
                ),
                const SizedBox(width: 6),
                _CompactFilterButton(
                  icon: Icons.tune_rounded,
                  label: 'Smart',
                  onTap: _showSmartFilterSheet,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (reports.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: _softCardDecoration(),
            child: Text(
              'No previous reports match the selected filters.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          ...reports.map(
            (report) => InkWell(
              onTap: () => _showPastReportDetails(report, controller),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD7E0E2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F2F1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.description_outlined,
                        color: Color(0xFF0B6F66),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _reportTitle(report),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F0FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _displayDate(report.uploadDateUtc),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF1E3A8A),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _statusPill(report),
                              _CompactIconButton(
                                icon: Icons.download_rounded,
                                color: const Color(0xFF0B6F66),
                                onTap: () => _exportPastReport(report),
                              ),
                              _CompactIconButton(
                                icon: Icons.share_outlined,
                                color: const Color(0xFF0B6F66),
                                onTap: () => _showShareReportSheet(report),
                              ),
                              _CompactIconButton(
                                icon: Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                                onTap: () => _confirmDeleteReport(report),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (controller.isLoadingPastReports)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (controller.showViewAllPastReportsButton)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: controller.loadAllPastReports,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: const BorderSide(color: Color(0xFFA7D2CB)),
                  foregroundColor: const Color(0xFF0B6F66),
                ),
                child: const Text(
                  'View All Reports',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<ReportDetails> _applyFilters(List<ReportDetails> reports) {
    final filtered = reports.where((report) {
      switch (_typeFilter) {
        case _TypeFilter.all:
          return true;
        case _TypeFilter.highRisk:
          return (report.riskLevel ?? '').toLowerCase() == 'high';
        case _TypeFilter.review:
          return (report.riskLevel ?? '').toLowerCase() == 'medium';
        case _TypeFilter.normal:
          return (report.riskLevel ?? '').toLowerCase() == 'low';
      }
    }).toList();

    final dateFiltered = _applyDateRangeFilter(filtered);
    final abnormalFiltered = _abnormalOnly
        ? dateFiltered.where(_reportHasAbnormal).toList()
        : dateFiltered;
    final categoryFiltered = _testTypeFilter == 'All'
        ? abnormalFiltered
        : abnormalFiltered.where((report) => _reportCategory(report) == _testTypeFilter).toList();

    categoryFiltered.sort((left, right) {
      final comparison = left.uploadDateUtc.compareTo(right.uploadDateUtc);
      return _dateFilter == _DateFilter.newestFirst ? -comparison : comparison;
    });

    return categoryFiltered;
  }

  Widget _statusPill(ReportDetails report) {
    final label = _statusLabel(report);
    final background = switch (label) {
      'NORMAL' => const Color(0xFFDFF4E2),
      'REVIEW' => const Color(0xFFF7EBB2),
      _ => const Color(0xFFF8D7D7),
    };
    final foreground = switch (label) {
      'NORMAL' => const Color(0xFF248A43),
      'REVIEW' => const Color(0xFFAF7B00),
      _ => const Color(0xFFC0392B),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  String _statusLabel(ReportDetails report) {
    final risk = (report.riskLevel ?? '').toLowerCase();
    if (risk == 'high') {
      return 'HIGH';
    }
    if (risk == 'medium') {
      return 'REVIEW';
    }
    return 'NORMAL';
  }

  String _reportTitle(ReportDetails report) {
    final names = report.tests
        .map((test) => test.testName.toLowerCase())
        .toList();
    if (names.any(
      (name) => name.contains('cholesterol') || name.contains('triglyceride'),
    )) {
      return 'Lipid Profile';
    }
    if (names.any((name) => name.contains('thyroid') || name.contains('tsh'))) {
      return 'Thyroid Profile';
    }
    if (names.any(
      (name) =>
          name.contains('wbc') ||
          name.contains('rbc') ||
          name.contains('hemoglobin'),
    )) {
      return 'Full Blood Count';
    }
    return 'Lab Report';
  }

  List<String> _availableReportCategories() {
    return const [
      'All',
      'Complete Blood Count',
      'Glucose & HbA1c',
      'Kidney Function',
      'Electrolytes',
      'Liver Function',
      'Lipid Profile',
      'Thyroid Profile',
      'Other',
    ];
  }

  bool _reportHasAbnormal(ReportDetails report) {
    return report.tests.any((test) {
      final status = test.status.toLowerCase();
      return status != 'normal' && status != 'optimal';
    });
  }

  String _reportCategory(ReportDetails report) {
    final names = report.tests.map((test) => test.testName.toLowerCase()).toList();
    if (names.any((name) => name.contains('cholesterol') || name.contains('triglyceride'))) {
      return 'Lipid Profile';
    }
    if (names.any((name) => name.contains('thyroid') || name.contains('tsh'))) {
      return 'Thyroid Profile';
    }
    if (names.any((name) => name.contains('glucose') || name.contains('sugar') || name.contains('hba1c'))) {
      return 'Glucose & HbA1c';
    }
    if (names.any((name) => name.contains('creatinine') || name.contains('urea') || name.contains('bun'))) {
      return 'Kidney Function';
    }
    if (names.any((name) => name.contains('sodium') || name.contains('potassium') || name.contains('chloride'))) {
      return 'Electrolytes';
    }
    if (names.any((name) => name.contains('alt') || name.contains('ast') || name.contains('alp') || name.contains('bilirubin'))) {
      return 'Liver Function';
    }
    if (names.any((name) => name.contains('wbc') || name.contains('rbc') || name.contains('hemoglobin') || name.contains('platelet'))) {
      return 'Complete Blood Count';
    }
    return 'Other';
  }

  List<ReportDetails> _applyDateRangeFilter(List<ReportDetails> reports) {
    if (_rangeFilter == _RangeFilter.all) return reports;
    final now = DateTime.now().toUtc();
    final cutoff = switch (_rangeFilter) {
      _RangeFilter.last7 => now.subtract(const Duration(days: 7)),
      _RangeFilter.last30 => now.subtract(const Duration(days: 30)),
      _RangeFilter.last90 => now.subtract(const Duration(days: 90)),
      _RangeFilter.last180 => now.subtract(const Duration(days: 180)),
      _RangeFilter.last365 => now.subtract(const Duration(days: 365)),
      _RangeFilter.all => now,
    };
    return reports.where((report) => report.uploadDateUtc.isAfter(cutoff)).toList();
  }

  String _reportSubtitle(ReportDetails report) {
    if (report.summary?.isNotEmpty == true) {
      return report.summary!.split('.').first;
    }

    if (report.rawText.isNotEmpty) {
      return report.rawText.split('\n').first.trim();
    }

    return 'AI analyzed report';
  }

  String _displayDate(DateTime date) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatRangeValue(num? value) {
    if (value == null) return 'N/A';
    final asDouble = value.toDouble();
    if (asDouble % 1 == 0) {
      return asDouble.toStringAsFixed(0);
    }
    return asDouble.toStringAsFixed(1);
  }

  String _resolveImageUrl(String imageUrl) => _resolveFileUrl(imageUrl);

  String _resolveFileUrl(String fileUrl) {
    if (fileUrl.startsWith('http://') || fileUrl.startsWith('https://')) {
      return fileUrl;
    }

    final baseUrl = widget.controller.baseUrl;
    return fileUrl.startsWith('/')
        ? '$baseUrl$fileUrl'
        : '$baseUrl/$fileUrl';
  }

  Future<void> _openReportPreview(
    ReportDetails report,
    ScannerController controller,
    bool allowLocalPreview,
  ) async {
    final pdfUrl = report.pdfUrl;
    if (pdfUrl != null && pdfUrl.isNotEmpty) {
      await _launchExternal(_resolveFileUrl(pdfUrl));
      return;
    }

    final imageUrl = report.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final resolved = _resolveFileUrl(imageUrl);
      if (resolved.toLowerCase().endsWith('.pdf')) {
        await _launchExternal(resolved);
        return;
      }
      _openFullImage(
        title: 'Report Image',
        image: Image.network(
          resolved,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _previewFallback(),
        ),
      );
      return;
    }

    if (allowLocalPreview && controller.selectedImages.isNotEmpty) {
      _openFullImage(
        title: controller.selectedImages.first.name,
        image: Image.file(
          File(controller.selectedImages.first.path),
          fit: BoxFit.contain,
        ),
      );
      return;
    }

    if (allowLocalPreview && controller.selectedPdf != null) {
      await _launchExternal(controller.selectedPdf!.path, isLocal: true);
      return;
    }

    _showMessage('Preview not available for this report.');
  }

  void _openFullImage({required String title, required Image image}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(title),
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0F172A),
            elevation: 0,
          ),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: image,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launchExternal(String url, {bool isLocal = false}) async {
    final uri = isLocal ? Uri.file(url) : Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showMessage('Unable to open the file.');
    }
  }

  Widget _previewFallback() {
    return Container(
      color: const Color(0xFFE3ECEC),
      alignment: Alignment.center,
      child: const Icon(
        Icons.insert_drive_file_outlined,
        size: 56,
        color: Color(0xFF748086),
      ),
    );
  }

  Widget _sectionTitle(String title, ThemeData theme) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
        color: const Color(0xFF1D2A44),
      ),
    );
  }

  BoxDecoration _softCardDecoration() {
    return BoxDecoration(
      color: const Color(0xFFEAF3F2),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFC8DDDA)),
    );
  }

  Widget _detailChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _latestReportDate(ReportDetails? current, List<ReportDetails> pastReports) {
    final dates = <DateTime>[
      if (current != null) current.uploadDateUtc,
      ...pastReports.map((report) => report.uploadDateUtc),
    ];
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.last;
  }

  Widget _buildRiskBanner(ReportDetails report, ThemeData theme) {
    final level = (report.riskLevel ?? 'Unknown').trim();
    final normalized = level.toLowerCase();

    Color accent;
    Color bg;
    Color border;
    IconData icon;

    if (normalized.contains('low') || normalized.contains('normal')) {
      accent = const Color(0xFF0F766E);
      bg = const Color(0xFFE7F6F4);
      border = const Color(0xFF9FD9CF);
      icon = Icons.verified_rounded;
    } else if (normalized.contains('moderate') || normalized.contains('medium')) {
      accent = const Color(0xFFB45309);
      bg = const Color(0xFFFFF3E0);
      border = const Color(0xFFF2C59A);
      icon = Icons.warning_rounded;
    } else if (normalized.contains('high') || normalized.contains('critical')) {
      accent = Colors.redAccent;
      bg = const Color(0xFFFFEAEA);
      border = const Color(0xFFF5B7B7);
      icon = Icons.report_rounded;
    } else {
      accent = const Color(0xFF64748B);
      bg = const Color(0xFFF1F5F9);
      border = const Color(0xFFCBD5E1);
      icon = Icons.help_outline_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Risk Level: $level',
              style: theme.textTheme.titleLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({Color accent, Color bg}) _criticalFindingColors(String severity) {
    final normalized = severity.trim().toLowerCase();

    if (normalized.contains('high') || normalized.contains('critical')) {
      return (accent: Colors.redAccent, bg: const Color(0xFFFFF1F1));
    }
    if (normalized.contains('normal') || normalized.contains('ok')) {
      return (accent: const Color(0xFF16A34A), bg: const Color(0xFFF0FDF4));
    }
    if (normalized.contains('medium') || normalized.contains('moderate')) {
      return (accent: const Color(0xFFF97316), bg: const Color(0xFFFFF7ED));
    }
    if (normalized.contains('low')) {
      return (accent: const Color(0xFF2563EB), bg: const Color(0xFFEFF6FF));
    }

    return (accent: const Color(0xFF64748B), bg: const Color(0xFFF1F5F9));
  }

  ButtonStyle _filterButtonStyle() {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: const BorderSide(color: Color(0xFF8FD6C9)), // Teal border
      foregroundColor: const Color(0xFF0B6F66), // Teal foreground
      backgroundColor: const Color(0xFFF1F8F7), // Light teal background
      minimumSize: const Size(0, 36),
    );
  }
}


class _AnalysisTabView extends StatefulWidget {
  final ScannerController controller;
  final VoidCallback onSelectPatient;
  final void Function(ReportDetails) onShareReport;
  final void Function(String) onShowMessage;

  const _AnalysisTabView({
    super.key,
    required this.controller,
    required this.onSelectPatient,
    required this.onShareReport,
    required this.onShowMessage,
  });

  @override
  State<_AnalysisTabView> createState() => _AnalysisTabViewState();
}

class _AnalysisTabViewState extends State<_AnalysisTabView> {
  String? _selectedTest;
  String _timeFilter = '6 Months';
  final GlobalKey _chartKey = GlobalKey();
  static const Map<String, String> _testCategoryMap = {
    // CBC
    'hemoglobin': 'Complete Blood Count',
    'wbc': 'Complete Blood Count',
    'rbc': 'Complete Blood Count',
    'platelet count': 'Complete Blood Count',
    'mcv': 'Complete Blood Count',
    'mch': 'Complete Blood Count',
    'mchc': 'Complete Blood Count',
    'rdw': 'Complete Blood Count',
    // Glucose
    'glucose': 'Glucose & HbA1c',
    'blood sugar (fasting)': 'Glucose & HbA1c',
    'blood sugar fasting': 'Glucose & HbA1c',
    'hba1c': 'Glucose & HbA1c',
    // Kidney
    'creatinine': 'Kidney Function',
    'urea': 'Kidney Function',
    'bun': 'Kidney Function',
    'uric acid': 'Kidney Function',
    // Electrolytes
    'sodium': 'Electrolytes',
    'potassium': 'Electrolytes',
    'chloride': 'Electrolytes',
    'calcium': 'Electrolytes',
    // Liver
    'alt': 'Liver Function',
    'ast': 'Liver Function',
    'alp': 'Liver Function',
    'bilirubin': 'Liver Function',
    // Lipids
    'cholesterol': 'Lipid Profile',
    'hdl': 'Lipid Profile',
    'ldl': 'Lipid Profile',
    'triglycerides': 'Lipid Profile',
  };
  static const List<String> _basicTests = [
    'Hemoglobin',
    'WBC',
    'RBC',
    'Platelet Count',
    'Glucose',
    'HbA1c',
    'Creatinine',
    'Urea',
    'Sodium',
    'Potassium',
    'ALT',
    'AST',
    'Cholesterol',
    'Triglycerides',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.fetchTrends();
    });
  }

  @override
  Widget build(BuildContext context) {
    final availableTests = widget.controller.availableTests;
    final hasTrendData = availableTests.isNotEmpty;
    final testsToShow = hasTrendData ? availableTests : _basicTests;
    final grouped = _groupTests(testsToShow);
    final allGroupedTests = grouped.values.expand((e) => e).toList();
    if (_selectedTest == null && allGroupedTests.isNotEmpty) {
      _selectedTest = allGroupedTests.first;
    }
    if (_selectedTest != null && !allGroupedTests.contains(_selectedTest)) {
      _selectedTest = allGroupedTests.isNotEmpty ? allGroupedTests.first : null;
    }

    final theme = Theme.of(context);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: _PatientSelectorBar(
                patient: widget.controller.selectedPatient,
                subtitle: widget.controller.selectedPatient != null
                    ? '${widget.controller.selectedPatient!.gender}, ${widget.controller.selectedPatient!.age}y'
                    : 'No patient selected',
                onTap: widget.onSelectPatient,
              ),
            ),
          ),
          if (grouped.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(theme),
            )
          else ...[
            if (!hasTrendData)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F8F7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFD1E7E4)),
                    ),
                    child: Text(
                      'No trend data yet. Showing basic tests so you can see the layout.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF0B6F66),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TimeFilterHeader(
                current: _timeFilter,
                onChanged: (value) => setState(() => _timeFilter = value),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final category = grouped.keys.elementAt(index);
                  final tests = grouped[category]!;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _CategoryGroup(
                      title: category,
                      tests: tests,
                      selectedTest: _selectedTest,
                      onSelect: (test) => setState(
                        () => _selectedTest = _selectedTest == test ? null : test,
                      ),
                      chartBuilder: (test) {
                        final points = widget.controller.getHistoryForTest(test);
                        return _buildChartSection(theme, test, points);
                      },
                    ),
                  );
                },
                childCount: grouped.length,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionSquareButton(
                        icon: Icons.share_outlined,
                        label: 'Share Report',
                        onTap: () {
                          final report = widget.controller.report;
                          if (report == null) {
                            widget.onShowMessage('Upload a report before sharing.');
                            return;
                          }
                          widget.onShareReport(report);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ActionSquareButton(
                        icon: Icons.calendar_today_outlined,
                        label: 'Book Test',
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: Colors.blueGrey.shade200),
            const SizedBox(height: 16),
            Text(
              'No trend data available yet',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.blueGrey.shade400),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload and analyze reports to see your progress.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<String>> _groupTests(List<String> tests) {
    final grouped = <String, List<String>>{};
    for (final test in tests) {
      final category = _testCategoryMap[test.toLowerCase()];
      if (category == null) continue;
      grouped.putIfAbsent(category, () => <String>[]).add(test);
    }
    return grouped;
  }

  Widget _buildChartSection(ThemeData theme, String testName, List<ReportTestPoint> points) {
    final filteredPoints = _filterPointsByTime(points, _timeFilter);

    return Container(
      key: _chartKey,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$testName Progress',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: _TestTrendChart(points: filteredPoints, testName: testName),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: const Border(
                left: BorderSide(color: Color(0xFF0F766E), width: 4),
              ),
            ),
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, color: const Color(0xFF475569)),
                children: [
                  const TextSpan(
                    text: 'Insight: ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E), fontStyle: FontStyle.italic),
                  ),
                  TextSpan(text: _generateInsight(filteredPoints, testName)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<ReportTestPoint> _filterPointsByTime(List<ReportTestPoint> points, String filter) {
    if (filter == 'All Time') return points;
    final now = DateTime.now();
    DateTime threshold;
    switch (filter) {
      case '1 Month': threshold = now.subtract(const Duration(days: 30)); break;
      case '3 Months': threshold = now.subtract(const Duration(days: 90)); break;
      case '6 Months': threshold = now.subtract(const Duration(days: 180)); break;
      case '1 Year': threshold = now.subtract(const Duration(days: 365)); break;
      default: return points;
    }
    return points.where((p) => p.date.isAfter(threshold)).toList();
  }

  String _getStatus(ReportTestPoint? point) {
    if (point == null) return 'Normal';
    final min = point.min;
    final max = point.max;
    if (min != null && point.value < min) return 'Low';
    if (max != null && point.value > max) return 'High';
    return 'Optimal';
  }

  String _generateInsight(List<ReportTestPoint> points, String testName) {
    if (points.length < 2) return 'Keep track of your reports to see detailed insights here.';
    final first = points.first.value;
    final last = points.last.value;
    final diff = last - first;
    final trend = diff > 0 ? 'slightly increased' : diff < 0 ? 'slightly decreased' : 'remained stable';
    final min = points.last.min;
    final max = points.last.max;
    final target = (min != null && max != null)
        ? (last >= min && last <= max)
            ? 'within the healthy target range'
            : 'outside the healthy range'
        : 'without a defined target range';
    return '$testName levels $trend over the selected period. Your current reading (${last.toStringAsFixed(1)} ${points.last.unit}) is $target.';
  }
}

class _TimeFilterHeader extends SliverPersistentHeaderDelegate {
  _TimeFilterHeader({
    required this.current,
    required this.onChanged,
  });

  final String current;
  final ValueChanged<String> onChanged;

  final List<String> _options = const [
    '1 Month',
    '3 Months',
    '6 Months',
    '1 Year',
    'All Time',
  ];

  @override
  double get minExtent => 64;

  @override
  double get maxExtent => 64;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFFF8FBFB),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _options.map((option) {
            final isSelected = current == option;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(option),
                selected: isSelected,
                onSelected: (_) => onChanged(option),
                selectedColor: const Color(0xFF0F766E),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                backgroundColor: const Color(0xFFF1F5F9),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                showCheckmark: false,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TimeFilterHeader oldDelegate) {
    return oldDelegate.current != current;
  }
}

class _PatientSelectorBar extends StatelessWidget {
  const _PatientSelectorBar({
    required this.patient,
    required this.subtitle,
    required this.onTap,
  });

  final Patient? patient;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD7E0E2)),
        ),
        child: Row(
          children: [
            _PatientAvatar(patient: patient, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient?.name ?? 'Select Patient',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF0B6F66)),
          ],
        ),
      ),
    );
  }
}

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({
    required this.patient,
    this.radius = 20,
    this.highlighted = false,
  });

  final Patient? patient;
  final double radius;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final initials = patient == null ? '?' : _patientInitials(patient!.name);
    final bgColor = highlighted ? const Color(0xFF0B6F66) : const Color(0xFFE0F2F1);
    final fgColor = highlighted ? Colors.white : const Color(0xFF0B6F66);

    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      child: Text(
        initials,
        style: TextStyle(
          color: fgColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _patientInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) {
    return '?';
  }
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  final first = parts.first.substring(0, 1);
  final last = parts.last.substring(0, 1);
  return (first + last).toUpperCase();
}

class _TestSummaryCard extends StatelessWidget {
  final String testName;
  final String status;
  final bool isSelected;
  final VoidCallback onTap;

  const _TestSummaryCard({
    required this.testName,
    required this.status,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    testName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  _getIconForTest(testName),
                  size: 16,
                  color: const Color(0xFF0F766E),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusAccent(status).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: _statusAccent(status),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForTest(String name) {
    final n = name.toLowerCase();
    if (n.contains('hemoglobin') || n.contains('rbc')) return Icons.water_drop;
    if (n.contains('wbc') || n.contains('biotech')) return Icons.biotech;
    if (n.contains('glucose')) return Icons.opacity;
    if (n.contains('cholesterol')) return Icons.monitor_heart;
    return Icons.science;
  }

  Color _statusAccent(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('high')) return Colors.redAccent;
    if (normalized.contains('low')) return const Color(0xFFB45309);
    return const Color(0xFF0F766E);
  }
}

class _TestTrendChart extends StatelessWidget {
  final List<ReportTestPoint> points;
  final String testName;

  const _TestTrendChart({required this.points, required this.testName});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const Center(child: Text('No data for this period'));

    final minVal = points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    final maxVal = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final rangeMin = points.last.min ?? minVal;
    final rangeMax = points.last.max ?? maxVal;
    final hasRangeMin = points.last.min != null;
    final hasRangeMax = points.last.max != null;

    final yMin = (minVal < rangeMin ? minVal : rangeMin) * 0.9;
    final yMax = (maxVal > rangeMax ? maxVal : rangeMax) * 1.1;

    final yInterval = ((yMax - yMin) == 0 ? 1 : (yMax - yMin) / 4).toDouble();

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipBorder: BorderSide(color: Colors.blueGrey.shade100),
            getTooltipColor: (_) => Colors.white,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.spotIndex;
                final point = points[index];
                final date = DateFormat('MMM dd, yyyy').format(point.date);
                final valueStr = point.unit.isNotEmpty
                    ? '${point.value} ${point.unit}'
                    : '${point.value}';
                return LineTooltipItem(
                  '$date\n$valueStr',
                  const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: yInterval,
          verticalInterval: 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.blueGrey.shade100,
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (value) => FlLine(
            color: Colors.blueGrey.shade50,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) return const SizedBox.shrink();
                if (points.length > 4 && index % (points.length ~/ 3) != 0 && index != points.length - 1) {
                   return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    DateFormat('MMM dd').format(points[index].date),
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: yInterval,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.blueGrey.shade100),
        ),
        minX: 0,
        maxX: (points.length - 1 == 0) ? 1 : (points.length - 1).toDouble(),
        minY: yMin.toDouble(),
        maxY: yMax.toDouble(),
        lineBarsData: [
          LineChartBarData(
            spots: points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value.toDouble())).toList(),
            isCurved: true,
            // curveSmoothness: 0.2, (removed deprecated/incorrect parameter)
            color: const Color(0xFF0F766E),
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                final point = points[index];
                final color = _pointColor(point);
                return FlDotCirclePainter(
                  radius: index == points.length - 1 ? 6 : 4,
                  color: color,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF2DD4BF).withOpacity(0.3),
                  const Color(0xFF2DD4BF).withOpacity(0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (hasRangeMin)
              HorizontalLine(
                y: rangeMin.toDouble(),
                color: const Color(0xFF2DD4BF).withOpacity(0.4),
                strokeWidth: 1,
                dashArray: [5, 5],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 9, fontWeight: FontWeight.bold),
                  labelResolver: (line) => 'MIN',
                ),
              ),
            if (hasRangeMax)
              HorizontalLine(
                y: rangeMax.toDouble(),
                color: const Color(0xFF2DD4BF).withOpacity(0.4),
                strokeWidth: 1,
                dashArray: [5, 5],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 9, fontWeight: FontWeight.bold),
                  labelResolver: (line) => 'MAX',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _pointColor(ReportTestPoint point) {
    final min = point.min;
    final max = point.max;
    if (max != null && point.value > max) return Colors.redAccent;
    if (min != null && point.value < min) return const Color(0xFFB45309);
    return const Color(0xFF0F766E);
  }
}

class _CategoryGroup extends StatelessWidget {
  const _CategoryGroup({
    required this.title,
    required this.tests,
    required this.selectedTest,
    required this.onSelect,
    required this.chartBuilder,
  });

  final String title;
  final List<String> tests;
  final String? selectedTest;
  final ValueChanged<String> onSelect;
  final Widget Function(String test) chartBuilder;

  @override
  Widget build(BuildContext context) {
    final isSelected = tests.contains(selectedTest);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tests.map((test) {
              final active = selectedTest == test;
              return ChoiceChip(
                label: Text(test),
                selected: active,
                onSelected: (_) => onSelect(test),
                selectedColor: const Color(0xFF0F766E).withOpacity(0.15),
                labelStyle: TextStyle(
                  color: active ? const Color(0xFF0F766E) : const Color(0xFF1F2937),
                  fontWeight: FontWeight.w700,
                ),
                side: const BorderSide(color: Color(0xFFD1E7E4)),
              );
            }).toList(),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: isSelected
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: chartBuilder(selectedTest!),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ActionSquareButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionSquareButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF0F766E), size: 28),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadAction extends StatelessWidget {
  const _UploadAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFD6E8E6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: const Color(0xFF1A5D58)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _DocumentChip extends StatelessWidget {
  const _DocumentChip({
    required this.icon,
    required this.label,
    required this.onDeleted,
  });

  final IconData icon;
  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close, size: 18),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF0B6F66) : const Color(0xFF97A2B8);

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactFilterButton extends StatelessWidget {
  const _CompactFilterButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF8FD6C9)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF0B6F66)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF0B6F66),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumActionCard extends StatelessWidget {
  const _PremiumActionCard({
    required this.overline,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.onTap,
  });

  final String overline;
  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8F7), // Light teal background
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD1E7E4), // Subtle teal border
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overline.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF0B6F66),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.blueGrey.shade600,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        color: color,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        splashRadius: 18,
      ),
    );
  }
}
