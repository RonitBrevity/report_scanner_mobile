import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  ApiClient({String? baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? _defaultBaseUrl(),
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  final Dio _dio;

  Dio get dio => _dio;
  String get baseUrl => _dio.options.baseUrl;

  static String _defaultBaseUrl() {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) {
      return override;
    }

    // OPTION 1 (USB Cable): Keep this as 'localhost' and run this command
    // in your terminal: adb reverse tcp:5219 tcp:5219
    //
    // OPTION 2 (Wi-Fi): Replace 'localhost' with your machine's local IP
    // address (e.g., '192.168.1.15').
    const String hostIp = 'localhost';

    if (kIsWeb) {
      //return 'http://localhost:5219';
      return 'http://103.92.121.94:9043';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        //return 'http://$hostIp:5219';
        return 'http://103.92.121.94:9043';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        //return 'http://localhost:5219';
        return 'http://103.92.121.94:9043';
      case TargetPlatform.fuchsia:
        //return 'http://localhost:5219';
        return 'http://103.92.121.94:9043';
    }
  }
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;

  static ApiException fromDioException(
    DioException exception, {
    String fallback = 'Unexpected network error.',
  }) {
    final responseData = exception.response?.data;
    if (responseData is Map<String, dynamic>) {
      final detail = responseData['detail'] ?? responseData['message'];
      if (detail is String && detail.isNotEmpty) {
        return ApiException(detail);
      }
    }
    if (responseData is String && responseData.isNotEmpty) {
      final lower = responseData.toLowerCase();
      if (lower.contains('<!doctype') || lower.contains('<html')) {
        final status = exception.response?.statusCode;
        return ApiException(
          status == null ? fallback : 'Server error ($status).',
        );
      }
      return ApiException(responseData);
    }
    return ApiException(fallback);
  }
}
