import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/patient.dart';
import '../models/report_details.dart';
import '../models/selected_upload_file.dart';
import '../services/api_client.dart';
import '../services/report_document_service.dart';
import '../services/report_scanner_service.dart';

class ScannerController extends ChangeNotifier {
  ScannerController(this._service, this._documentService);

  final ReportScannerService _service;
  final ReportDocumentService _documentService;
  String get baseUrl => _service.baseUrl;

  List<Patient> _patients = <Patient>[];
  Patient? _selectedPatient;
  List<XFile> _selectedImages = <XFile>[];
  SelectedUploadFile? _selectedPdf;
  ReportDetails? _report;
  final List<ReportDetails> _pastReports = <ReportDetails>[];
  final List<ReportDetails> _allHistoricalReports = <ReportDetails>[];
  final Map<String, List<ReportTestPoint>> _testTrends = <String, List<ReportTestPoint>>{};
  String? _error;
  bool _isLoadingPatients = false;
  bool _isSubmitting = false;
  bool _isLoadingPastReports = false;
  bool _hasMorePastReports = false;
  int _pastReportsRequested = 0;
  static const int _incrementalPastReportLimit = 5;

  List<Patient> get patients => _patients;
  Patient? get selectedPatient => _selectedPatient;
  List<XFile> get selectedImages => List<XFile>.unmodifiable(_selectedImages);
  SelectedUploadFile? get selectedPdf => _selectedPdf;
  ReportDetails? get report => _report;
  List<ReportDetails> get pastReports => List<ReportDetails>.unmodifiable(_pastReports);
  String? get error => _error;
  bool get isLoadingPatients => _isLoadingPatients;
  bool get isSubmitting => _isSubmitting;
  bool get isLoadingPastReports => _isLoadingPastReports;
  bool get isBusy => _isLoadingPatients || _isSubmitting;
  bool get showViewAllPastReportsButton =>
      _hasMorePastReports && _pastReportsRequested >= _incrementalPastReportLimit;
  bool get hasSelectedDocuments => _selectedPdf != null || _selectedImages.isNotEmpty;

  List<String> get availableTests => _testTrends.keys.toList()..sort();

  List<ReportTestPoint> getHistoryForTest(String testName) =>
      _testTrends[testName] ?? <ReportTestPoint>[];
  bool get canLoadNextPastReport =>
      !_isLoadingPastReports &&
      _hasMorePastReports &&
      _pastReportsRequested < _incrementalPastReportLimit;

  Future<void> loadPatients() async {
    _isLoadingPatients = true;
    _error = null;
    notifyListeners();

    try {
      _patients = await _service.getPatients();
      if (_patients.isNotEmpty) {
        _selectedPatient = _patients.first;
        _resetReportState(notify: false);
        await loadInitialPastReports(notifyAtStart: false);
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Failed to load patients.';
    } finally {
      _isLoadingPatients = false;
      notifyListeners();
    }
  }

  void setSelectedPatient(Patient? patient) {
    _selectedPatient = patient;
    _resetReportState(notify: false);
    if (_selectedPatient != null) {
      unawaited(loadInitialPastReports());
    }
    notifyListeners();
  }

  void addPatient(Patient patient) {
    _patients = [..._patients, patient];
    _selectedPatient ??= patient;
    notifyListeners();
  }

  Future<Patient> createPatient({
    required String name,
    required int age,
    required String gender,
    String? patientId,
  }) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();
    try {
      final created = await _service.createPatient(
        name: name,
        age: age,
        gender: gender,
        patientId: patientId,
      );
      addPatient(created);
      _selectedPatient = created;
      return created;
    } on ApiException catch (e) {
      _error = e.message;
      throw ApiException(e.message);
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<Patient> updatePatient({
    required String patientId,
    required String name,
    required int age,
    required String gender,
  }) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _service.updatePatient(
        patientId: patientId,
        name: name,
        age: age,
        gender: gender,
      );

      _patients = _patients
          .map((p) => p.patientId == patientId ? updated : p)
          .toList();
      if (_selectedPatient?.patientId == patientId) {
        _selectedPatient = updated;
      }
      notifyListeners();
      return updated;
    } on ApiException catch (e) {
      _error = e.message;
      throw ApiException(e.message);
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> deletePatient(String patientId) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();
    try {
      await _service.deletePatient(patientId);
      _patients = _patients.where((p) => p.patientId != patientId).toList();
      if (_selectedPatient?.patientId == patientId) {
        _selectedPatient = _patients.isNotEmpty ? _patients.first : null;
        _resetReportState(notify: false);
      }
      await loadInitialPastReports(notifyAtStart: false);
    } on ApiException catch (e) {
      _error = e.message;
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void setSelectedImages(List<XFile> images) {
    _selectedImages = images.take(4).toList();
    if (_selectedImages.isNotEmpty) {
      _selectedPdf = null;
    }
    _resetReportState(notify: false, clearPastReports: false);
    notifyListeners();
  }

  void removeSelectedImage(XFile image) {
    _selectedImages = _selectedImages.where((item) => item.path != image.path).toList();
    _resetReportState(notify: false, clearPastReports: false);
    notifyListeners();
  }

  void setSelectedPdf(SelectedUploadFile? pdf) {
    _selectedPdf = pdf;
    if (pdf != null) {
      _selectedImages = <XFile>[];
    }
    _resetReportState(notify: false, clearPastReports: false);
    notifyListeners();
  }

  Future<void> uploadAndAnalyze() async {
    if (_selectedPatient == null || !hasSelectedDocuments) {
      _error = 'Please select a patient and upload images or a PDF first.';
      notifyListeners();
      return;
    }

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final preparedUpload = await _documentService.prepareForUpload(
        images: _selectedImages,
        pdfFile: _selectedPdf,
      );
      _report = await _service.uploadAndAnalyze(
        patientId: _selectedPatient!.patientId,
        filePath: preparedUpload.filePath,
        fileName: preparedUpload.fileName,
        originalPdfPath: preparedUpload.originalPdfPath,
        originalPdfName: preparedUpload.originalPdfName,
      );
      await loadInitialPastReports(notifyAtStart: false);

      // Reset the selection UI after a successful scan.
      _selectedImages = <XFile>[];
      _selectedPdf = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Upload/analyze failed.';
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<String> exportCurrentReportPdf() async {
    if (_report == null || _selectedPatient == null) {
      throw StateError('Current report is not available.');
    }

    return _documentService.exportReportPdf(
      report: _report!,
      patient: _selectedPatient!,
    );
  }

  Future<String> exportPastReportPdf(ReportDetails report) async {
    if (_selectedPatient == null) {
      throw StateError('Patient is not available.');
    }

    return _documentService.exportReportPdf(
      report: report,
      patient: _selectedPatient!,
    );
  }

  String buildReportSummary(ReportDetails report) => _documentService.buildPreviewSummary(report);

  Future<void> loadInitialPastReports({bool notifyAtStart = true}) async {
    if (_selectedPatient == null) {
      return;
    }

    _isLoadingPastReports = true;
    _error = null;
    if (notifyAtStart) {
      notifyListeners();
    }

    try {
      final reports = await _service.getPatientReports(
        patientId: _selectedPatient!.patientId,
        skip: 0,
        take: _incrementalPastReportLimit,
        excludeReportId: _report?.reportId,
      );

      _pastReports
        ..clear()
        ..addAll(reports);
      _pastReportsRequested = _pastReports.length;
      _hasMorePastReports = reports.length == _incrementalPastReportLimit;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Failed to load past reports.';
    } finally {
      _isLoadingPastReports = false;
      notifyListeners();
    }
  }

  Future<void> loadNextPastReport({bool notifyAtStart = true}) async {
    if (_selectedPatient == null || !canLoadNextPastReport) {
      return;
    }

    _isLoadingPastReports = true;
    if (notifyAtStart) {
      notifyListeners();
    }

    try {
      final reports = await _service.getPatientReports(
        patientId: _selectedPatient!.patientId,
        skip: _pastReports.length,
        take: 1,
        excludeReportId: _report?.reportId,
      );

      if (reports.isEmpty) {
        _hasMorePastReports = false;
      } else {
        _pastReports.addAll(reports);
        _pastReportsRequested += 1;
        _hasMorePastReports = reports.length == 1;
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Failed to load past reports.';
    } finally {
      _isLoadingPastReports = false;
      notifyListeners();
    }
  }

  Future<void> loadAllPastReports() async {
    if (_selectedPatient == null || _isLoadingPastReports || !_hasMorePastReports) {
      return;
    }

    _isLoadingPastReports = true;
    notifyListeners();

    try {
      final reports = await _service.getPatientReports(
        patientId: _selectedPatient!.patientId,
        skip: _pastReports.length,
        take: 100,
        excludeReportId: _report?.reportId,
      );

      _pastReports.addAll(reports);
      _hasMorePastReports = false;
      _updateHistoricalTrends();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Failed to load past reports.';
    } finally {
      _isLoadingPastReports = false;
      notifyListeners();
    }
  }

  Future<void> fetchTrends() async {
    if (_selectedPatient == null) return;

    _isLoadingPastReports = true;
    notifyListeners();

    try {
      // Fetch all reports to build trends
      final allReports = await _service.getPatientReports(
        patientId: _selectedPatient!.patientId,
        skip: 0,
        take: 100,
      );
      _allHistoricalReports.clear();
      _allHistoricalReports.addAll(allReports);
      _updateHistoricalTrends();
    } catch (e) {
      _error = 'Failed to fetch trends: $e';
    } finally {
      _isLoadingPastReports = false;
      notifyListeners();
    }
  }

  void _updateHistoricalTrends() {
    _testTrends.clear();
    // Combine current report if available with historical ones
    final all = <ReportDetails>[..._allHistoricalReports];
    if (_report != null && !all.any((r) => r.reportId == _report!.reportId)) {
      all.add(_report!);
    }

    // Sort by date ascending for charts
    all.sort((a, b) => a.uploadDateUtc.compareTo(b.uploadDateUtc));

    for (final report in all) {
      for (final test in report.tests) {
        final name = test.testName;
        _testTrends.putIfAbsent(name, () => <ReportTestPoint>[]);
        _testTrends[name]!.add(
          ReportTestPoint(
            date: report.uploadDateUtc,
            value: test.value,
            min: test.rangeMin,
            max: test.rangeMax,
            unit: test.unit.isNotEmpty ? test.unit : _extractUnit(test.interpretation),
          ),
        );
      }
    }
    notifyListeners();
  }

  String _extractUnit(String interpretation) {
    // Simple heuristic to extract units from interpretation
    final units = [
      'g/dL', 'mg/dL', '10³/µL', '10⁶/µL', 'pg', 'fL', '%', 'U/L', 'mmol/L', 'µg/dL', 'mIU/L', 'ng/mL'
    ];
    for (final unit in units) {
      if (interpretation.contains(unit)) return unit;
    }
    return '';
  }

  Future<bool> deleteReport(String reportId) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      await _service.deleteReport(reportId);
      
      // If the current open report is deleted, clear it
      if (_report?.reportId == reportId) {
        _report = null;
      }
      
      // Remove from past reports list
      _pastReports.removeWhere((r) => r.reportId == reportId);
      
      // Remove from historical reports used for trends
      _allHistoricalReports.removeWhere((r) => r.reportId == reportId);
      _updateHistoricalTrends();
      
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      _error = 'Failed to delete report.';
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<String> createShareLink({
    required String reportId,
    String? targetMobileNumber,
    String expiryOption = '1m',
  }) async {
    try {
      return await _service.createShareLink(
        reportId: reportId,
        targetMobileNumber: targetMobileNumber,
        expiryOption: expiryOption,
      );
    } on ApiException catch (e) {
      throw ApiException(e.message);
    }
  }

  Future<void> requestShareOtp({
    required String shareId,
    required String mobileNumber,
  }) async {
    try {
      await _service.requestShareOtp(
        shareId: shareId,
        mobileNumber: mobileNumber,
      );
    } on ApiException catch (e) {
      throw ApiException(e.message);
    }
  }

  Future<ReportDetails> verifyShareOtp({
    required String shareId,
    required String mobileNumber,
    required String otp,
  }) async {
    try {
      return await _service.verifyShareOtp(
        shareId: shareId,
        mobileNumber: mobileNumber,
        otp: otp,
      );
    } on ApiException catch (e) {
      throw ApiException(e.message);
    }
  }

  void _resetReportState({bool notify = true, bool clearPastReports = true}) {
    _report = null;
    _error = null;
    if (clearPastReports) {
      _pastReports.clear();
      _isLoadingPastReports = false;
      _hasMorePastReports = false;
      _pastReportsRequested = 0;
    }

    if (notify) {
      notifyListeners();
    }
  }
}

class ReportTestPoint {
  final DateTime date;
  final num value;
  final num? min;
  final num? max;
  final String unit;

  ReportTestPoint({
    required this.date,
    required this.value,
    this.min,
    this.max,
    required this.unit,
  });
}
