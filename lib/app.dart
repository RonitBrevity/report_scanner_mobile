import 'package:flutter/material.dart';

import 'controllers/scanner_controller.dart';
import 'screens/scanner_home_page.dart';
import 'services/api_client.dart';
import 'services/report_document_service.dart';
import 'services/report_scanner_service.dart';

class ReportScannerApp extends StatefulWidget {
  const ReportScannerApp({super.key});

  @override
  State<ReportScannerApp> createState() => _ReportScannerAppState();
}

class _ReportScannerAppState extends State<ReportScannerApp> {
  late final ApiClient _apiClient;
  late final ReportScannerService _service;
  late final ReportDocumentService _documentService;
  late final ScannerController _controller;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _service = ReportScannerService(_apiClient);
    _documentService = ReportDocumentService();
    _controller = ScannerController(_service, _documentService);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Report Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: ScannerHomePage(controller: _controller),
    );
  }
}
