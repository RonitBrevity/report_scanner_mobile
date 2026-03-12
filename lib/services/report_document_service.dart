import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/patient.dart';
import '../models/report_details.dart';
import '../models/selected_upload_file.dart';

class PreparedUploadDocument {
  const PreparedUploadDocument({
    required this.fileName,
    required this.filePath,
  });

  final String fileName;
  final String filePath;
}

class ReportDocumentService {
  Future<PreparedUploadDocument> prepareForUpload({
    required List<XFile> images,
    SelectedUploadFile? pdfFile,
  }) async {
    if (pdfFile != null) {
      return PreparedUploadDocument(
        fileName: pdfFile.name,
        filePath: pdfFile.path,
      );
    }

    if (images.isEmpty) {
      throw StateError('No upload document selected.');
    }

    if (images.length == 1) {
      return PreparedUploadDocument(
        fileName: images.first.name,
        filePath: images.first.path,
      );
    }

    final tempDirectory = await getTemporaryDirectory();
    final stitchedImage = await _stitchImages(images);
    if (stitchedImage != null) {
      final jpgBytes = img.encodeJpg(stitchedImage, quality: 85);
      final file = File(
        '${tempDirectory.path}${Platform.pathSeparator}multi_report_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(jpgBytes);
      return PreparedUploadDocument(
        fileName: file.uri.pathSegments.last,
        filePath: file.path,
      );
    }

    final document = pw.Document();
    for (final image in images) {
      final bytes = await image.readAsBytes();
      final memoryImage = pw.MemoryImage(bytes);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(
            child: pw.Image(memoryImage, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}multi_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await document.save());

    return PreparedUploadDocument(
      fileName: file.uri.pathSegments.last,
      filePath: file.path,
    );
  }

  Future<String> exportReportPdf({
    required ReportDetails report,
    required Patient patient,
  }) async {
    final document = pw.Document();
    final abnormalTests = report.tests.where((test) => test.status != 'Normal').toList();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            'HealthScan AI Report Summary',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Patient: ${patient.name}'),
          pw.Text('Gender/Age: ${patient.gender}, ${patient.age}y'),
          pw.Text('Report date: ${_formatDate(report.uploadDateUtc)}'),
          pw.Text('Risk level: ${report.riskLevel ?? 'Unknown'}'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Overall Summary',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(_buildTotalSummary(report)),
          pw.SizedBox(height: 16),
          pw.Text(
            'Critical Findings',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (report.criticalFindings.isEmpty)
            pw.Text('No critical findings were identified.')
          else
            ...report.criticalFindings.map(
              (finding) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text('- ${finding.finding} (${finding.severity})'),
              ),
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Abnormal Test Summary',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (abnormalTests.isEmpty)
            pw.Text('All extracted tests are within the normal range.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Test', 'Value', 'Range', 'Status'],
              data: abnormalTests
                  .map(
                    (test) => [
                      test.testName,
                      '${test.value}',
                      '${test.rangeMin ?? 'N/A'} - ${test.rangeMax ?? 'N/A'}',
                      test.status,
                    ],
                  )
                  .toList(),
            ),
        ],
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}healthscan_${report.reportId}.pdf',
    );
    await file.writeAsBytes(await document.save());
    return file.path;
  }

  String buildPreviewSummary(ReportDetails report) => _buildTotalSummary(report);

  String _buildTotalSummary(ReportDetails report) {
    final abnormalTests = report.tests.where((test) => test.status != 'Normal').toList();
    final findings = report.criticalFindings.map((finding) => finding.finding).join(', ');

    if (abnormalTests.isEmpty && findings.isEmpty) {
      return report.summary?.isNotEmpty == true
          ? report.summary!
          : 'The report does not contain any abnormal findings in the extracted data.';
    }

    final testSummary = abnormalTests.isEmpty
        ? 'No abnormal lab values were extracted.'
        : abnormalTests
            .map((test) => '${test.testName} is ${test.status.toLowerCase()} at ${test.value}')
            .join('. ');

    final findingSummary = findings.isEmpty
        ? 'No critical findings were flagged.'
        : 'Critical findings include $findings.';

    final baseSummary = report.summary?.isNotEmpty == true ? '${report.summary!} ' : '';
    return '$baseSummary$testSummary. $findingSummary'.trim();
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<img.Image?> _stitchImages(List<XFile> images) async {
    final decodedImages = <img.Image>[];

    for (final image in images) {
      final bytes = await image.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        continue;
      }
      decodedImages.add(decoded);
    }

    if (decodedImages.isEmpty) {
      return null;
    }

    final maxWidth = decodedImages.map((i) => i.width).reduce((a, b) => a > b ? a : b);
    final totalHeight = decodedImages.fold<int>(0, (sum, i) => sum + i.height);

    final canvas = img.Image(width: maxWidth, height: totalHeight);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    var offsetY = 0;
    for (final image in decodedImages) {
      final offsetX = ((maxWidth - image.width) / 2).round();
      img.compositeImage(canvas, image, dstX: offsetX, dstY: offsetY);
      offsetY += image.height;
    }

    return canvas;
  }
}
