class ReportDetails {
  final String reportId;
  final String patientId;
  final DateTime uploadDateUtc;
  final String? imageUrl;
  final String? pdfUrl;
  final String rawText;
  final String? riskLevel;
  final String? summary;
  final List<ReportTest> tests;
  final List<CriticalFinding> criticalFindings;

  bool get isNoReportFound => tests.isEmpty;

  const ReportDetails({
    required this.reportId,
    required this.patientId,
    required this.uploadDateUtc,
    required this.imageUrl,
    required this.pdfUrl,
    required this.rawText,
    required this.riskLevel,
    required this.summary,
    required this.tests,
    required this.criticalFindings,
  });

  factory ReportDetails.fromJson(Map<String, dynamic> json) => ReportDetails(
        reportId: json['reportId'] as String,
        patientId: json['patientId'] as String,
        uploadDateUtc: DateTime.parse(json['uploadDateUtc'] as String),
        imageUrl: json['imageUrl'] as String?,
        pdfUrl: json['pdfUrl'] as String?,
        rawText: (json['rawText'] as String?) ?? '',
        riskLevel: json['riskLevel'] as String?,
        summary: json['summary'] as String?,
        tests: ((json['tests'] as List<dynamic>?) ?? <dynamic>[])
            .map((item) => ReportTest.fromJson(item as Map<String, dynamic>))
            .toList(),
        criticalFindings: ((json['criticalFindings'] as List<dynamic>?) ?? <dynamic>[])
            .map((item) => CriticalFinding.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class ReportTest {
  final String testName;
  final num value;
  final String unit;
  final num? rangeMin;
  final num? rangeMax;
  final String status;
  final String interpretation;

  const ReportTest({
    required this.testName,
    required this.value,
    required this.unit,
    required this.rangeMin,
    required this.rangeMax,
    required this.status,
    required this.interpretation,
  });

  factory ReportTest.fromJson(Map<String, dynamic> json) => ReportTest(
        testName: json['testName'] as String,
        value: json['value'] as num,
        unit: (json['unit'] as String?) ?? '',
        rangeMin: json['rangeMin'] as num?,
        rangeMax: json['rangeMax'] as num?,
        status: json['status'] as String,
        interpretation: (json['interpretation'] as String?) ?? '',
      );
}

class CriticalFinding {
  final String finding;
  final String severity;

  const CriticalFinding({
    required this.finding,
    required this.severity,
  });

  factory CriticalFinding.fromJson(Map<String, dynamic> json) => CriticalFinding(
        finding: json['finding'] as String,
        severity: json['severity'] as String,
      );
}
