import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

import '../models/patient.dart';
import '../models/report_details.dart';
import '../models/selected_upload_file.dart';

class PreparedUploadDocument {
  const PreparedUploadDocument({
    required this.fileName,
    required this.filePath,
    this.originalPdfName,
    this.originalPdfPath,
  });

  final String fileName;
  final String filePath;
  final String? originalPdfName;
  final String? originalPdfPath;
}

class ReportDocumentService {
  static const int _maxPdfPages = 3;
  static const int _pdfMaxDimension = 1800;
  static const int _jpgQuality = 85;

  Future<PreparedUploadDocument> prepareForUpload({
    required List<XFile> images,
    SelectedUploadFile? pdfFile,
  }) async {
    if (pdfFile != null) {
      final converted = await _convertPdfToJpg(pdfFile.path);
      if (converted != null) {
        return converted;
      }
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
      return _saveJpg(
        stitchedImage,
        tempDirectory,
        'multi_report_${DateTime.now().millisecondsSinceEpoch}',
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

    return _stitchDecodedImages(decodedImages);
  }

  img.Image? _stitchDecodedImages(List<img.Image> decodedImages) {
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

  Future<PreparedUploadDocument> _saveJpg(
    img.Image image,
    Directory tempDirectory,
    String baseName,
  ) async {
    final jpgBytes = img.encodeJpg(image, quality: _jpgQuality);
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}$baseName.jpg',
    );
    await file.writeAsBytes(jpgBytes);
    return PreparedUploadDocument(
      fileName: file.uri.pathSegments.last,
      filePath: file.path,
    );
  }

  Future<PreparedUploadDocument?> _convertPdfToJpg(String pdfPath) async {
    try {
      final document = await pdfx.PdfDocument.openFile(pdfPath);
      final pagesToRender = document.pagesCount < _maxPdfPages
          ? document.pagesCount
          : _maxPdfPages;
      final renderedImages = <img.Image>[];

      for (var pageIndex = 1; pageIndex <= pagesToRender; pageIndex++) {
        final page = await document.getPage(pageIndex);
        final target = _scaleToMax(
          page.width,
          page.height,
          _pdfMaxDimension,
        );
        final pageImage = await page.render(
          width: target.$1.toDouble(),
          height: target.$2.toDouble(),
          format: pdfx.PdfPageImageFormat.png,
        );
        await page.close();
        if (pageImage == null || pageImage.bytes.isEmpty) {
          continue;
        }
        final decoded = img.decodeImage(pageImage.bytes);
        if (decoded != null) {
          renderedImages.add(decoded);
        }
      }

      await document.close();

      if (renderedImages.isEmpty) {
        return null;
      }

      final stitched = _stitchDecodedImages(renderedImages) ?? renderedImages.first;
      final tempDirectory = await getTemporaryDirectory();
      final prepared = await _saveJpg(
        stitched,
        tempDirectory,
        'pdf_report_${DateTime.now().millisecondsSinceEpoch}',
      );
      return PreparedUploadDocument(
        fileName: prepared.fileName,
        filePath: prepared.filePath,
        originalPdfName: File(pdfPath).uri.pathSegments.last,
        originalPdfPath: pdfPath,
      );
    } catch (_) {
      return null;
    }
  }

  (int, int) _scaleToMax(double width, double height, int maxDimension) {
    final maxSide = width > height ? width : height;
    if (maxSide <= maxDimension) {
      return (width.round(), height.round());
    }
    final scale = maxDimension / maxSide;
    return ((width * scale).round(), (height * scale).round());
  }
}
