import 'package:dio/dio.dart';

import '../models/patient.dart';
import '../models/report_details.dart';
import 'api_client.dart';

class ReportScannerService {
  ReportScannerService(this._client);

  final ApiClient _client;
  String get baseUrl => _client.baseUrl;

  Future<List<Patient>> getPatients() async {
    try {
      final response = await _client.dio.get<List<dynamic>>('/api/patients');
      final list = response.data ?? <dynamic>[];
      return list
          .map((item) => Patient.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e, fallback: 'Failed to load patients.');
    }
  }

  Future<ReportDetails> uploadAndAnalyze({
    required String patientId,
    required String filePath,
    required String fileName,
    String? originalPdfPath,
    String? originalPdfName,
  }) async {
    try {
      final formData = FormData.fromMap({
        'patientId': patientId,
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        if (originalPdfPath != null && originalPdfName != null)
          'originalPdf': await MultipartFile.fromFile(
            originalPdfPath,
            filename: originalPdfName,
          ),
      });

      final uploadResponse = await _client.dio.post<Map<String, dynamic>>(
        '/api/reports/upload',
        data: formData,
      );

      final reportId = uploadResponse.data?['reportId'] as String?;
      if (reportId == null || reportId.isEmpty) {
        throw ApiException('Upload completed but report ID was missing.');
      }

      final reportResponse = await _client.dio.get<Map<String, dynamic>>(
        '/api/reports/$reportId',
      );

      final body = reportResponse.data;
      if (body == null) {
        throw ApiException('Report details were empty.');
      }

      return ReportDetails.fromJson(body);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e, fallback: 'Upload/analyze failed.');
    }
  }

  Future<List<ReportDetails>> getPatientReports({
    required String patientId,
    int skip = 0,
    int take = 1,
    String? excludeReportId,
  }) async {
    try {
      final response = await _client.dio.get<List<dynamic>>(
        '/api/reports/patient/$patientId',
        queryParameters: {
          'skip': skip,
          'take': take,
          if (excludeReportId != null && excludeReportId.isNotEmpty)
            'excludeReportId': excludeReportId,
        },
      );

      final list = response.data ?? <dynamic>[];
      return list
          .map((item) => ReportDetails.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e, fallback: 'Failed to load past reports.');
    }
  }

  Future<void> deleteReport(String reportId) async {
    try {
      await _client.dio.delete('/api/reports/$reportId');
    } on DioException catch (e) {
      // Some servers (IIS) block DELETE; fall back to POST.
      final status = e.response?.statusCode;
      if (status == 405) {
        try {
          await _client.dio.post('/api/reports/$reportId/delete');
          return;
        } on DioException catch (postError) {
          throw ApiException.fromDioException(postError, fallback: 'Failed to delete report.');
        }
      }
      throw ApiException.fromDioException(e, fallback: 'Failed to delete report.');
    }
  }

  Future<Patient> createPatient({
    required String name,
    required int age,
    required String gender,
    String? patientId,
  }) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/api/patients',
        data: {
          if (patientId != null && patientId.isNotEmpty) 'patientId': patientId,
          'name': name,
          'age': age,
          'gender': gender,
        },
      );
      final body = response.data;
      if (body == null) throw ApiException('Patient creation failed.');
      return Patient.fromJson(body);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e, fallback: 'Failed to create patient.');
    }
  }

  Future<Patient> updatePatient({
    required String patientId,
    required String name,
    required int age,
    required String gender,
  }) async {
    try {
      final response = await _client.dio.put<Map<String, dynamic>>(
        '/api/patients/$patientId',
        data: {
          'name': name,
          'age': age,
          'gender': gender,
        },
      );
      final body = response.data;
      if (body == null) throw ApiException('Patient update failed.');
      return Patient.fromJson(body);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e, fallback: 'Failed to update patient.');
    }
  }

  Future<void> deletePatient(String patientId) async {
    try {
      await _client.dio.delete('/api/patients/$patientId');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 405) {
        try {
          await _client.dio.post('/api/patients/$patientId/delete');
          return;
        } on DioException catch (postError) {
          throw ApiException.fromDioException(postError, fallback: 'Failed to delete patient.');
        }
      }
      throw ApiException.fromDioException(e, fallback: 'Failed to delete patient.');
    }
  }

  Future<String> createShareLink({
    required String reportId,
    String? targetMobileNumber,
    String expiryOption = '1m',
  }) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/api/reportshare/create',
        data: {
          'reportId': reportId,
          if (targetMobileNumber != null && targetMobileNumber.isNotEmpty)
            'targetMobileNumber': targetMobileNumber,
          'expiryOption': expiryOption,
        },
      );
      final body = response.data;
      final shareUrl = body?['shareUrl'] as String?;
      if (shareUrl == null || shareUrl.isEmpty) {
        throw ApiException('Share link was empty.');
      }
      return shareUrl;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e, fallback: 'Failed to create share link.');
    }
  }

  Future<void> requestShareOtp({
    required String shareId,
    required String mobileNumber,
  }) async {
    try {
      await _client.dio.post<Map<String, dynamic>>(
        '/api/reportshare/$shareId/request-otp',
        data: {
          'mobileNumber': mobileNumber,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e, fallback: 'Failed to send OTP.');
    }
  }

  Future<ReportDetails> verifyShareOtp({
    required String shareId,
    required String mobileNumber,
    required String otp,
  }) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/api/reportshare/$shareId/verify',
        data: {
          'mobileNumber': mobileNumber,
          'otp': otp,
        },
      );
      final body = response.data;
      if (body == null) {
        throw ApiException('Shared report details were empty.');
      }
      return ReportDetails.fromJson(body);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e, fallback: 'Failed to verify OTP.');
    }
  }
}
