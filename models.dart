// lib/models/models.dart
// All data models mirroring the FastAPI backend response shapes.

class FraudIndicator {
  final String name;
  final bool detected;
  final String severity; // "low" | "medium" | "high" | "critical"
  final String description;

  const FraudIndicator({
    required this.name,
    required this.detected,
    required this.severity,
    required this.description,
  });

  factory FraudIndicator.fromJson(Map<String, dynamic> json) {
    return FraudIndicator(
      name: json['name'] as String,
      detected: json['detected'] as bool,
      severity: json['severity'] as String,
      description: json['description'] as String,
    );
  }
}

class PaymentInfo {
  final bool containsPaymentInfo;
  final String? extractedAmount;
  final String? extractedDate;
  final String? extractedId;

  const PaymentInfo({
    required this.containsPaymentInfo,
    this.extractedAmount,
    this.extractedDate,
    this.extractedId,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) {
    return PaymentInfo(
      containsPaymentInfo: json['contains_payment_info'] as bool,
      extractedAmount: json['extracted_amount'] as String?,
      extractedDate: json['extracted_date'] as String?,
      extractedId: json['extracted_id'] as String?,
    );
  }
}

class ExtractedData {
  final String ocrText;
  final PaymentInfo paymentInfo;

  const ExtractedData({required this.ocrText, required this.paymentInfo});

  factory ExtractedData.fromJson(Map<String, dynamic> json) {
    return ExtractedData(
      ocrText: json['ocr_text'] as String,
      paymentInfo: PaymentInfo.fromJson(json['payment_info'] as Map<String, dynamic>),
    );
  }
}

class AnalysisResult {
  final String id;
  final String analysisType; // "text" | "url" | "image"
  final int scamScore;
  final String riskLevel;
  final double confidence;
  final List<FraudIndicator> indicators;
  final String recommendation;
  final String summary;
  final DateTime timestamp;
  final ExtractedData? extractedData;

  const AnalysisResult({
    required this.id,
    required this.analysisType,
    required this.scamScore,
    required this.riskLevel,
    required this.confidence,
    required this.indicators,
    required this.recommendation,
    required this.summary,
    required this.timestamp,
    this.extractedData,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      id: json['id'] as String,
      analysisType: json['analysis_type'] as String,
      scamScore: json['scam_score'] as int,
      riskLevel: json['risk_level'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      indicators: (json['indicators'] as List<dynamic>)
          .map((e) => FraudIndicator.fromJson(e as Map<String, dynamic>))
          .toList(),
      recommendation: json['recommendation'] as String,
      summary: json['summary'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      extractedData: json['extracted_data'] != null
          ? ExtractedData.fromJson(json['extracted_data'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'analysis_type': analysisType,
      'scam_score': scamScore,
      'risk_level': riskLevel,
      'confidence': confidence,
      'indicators': indicators
          .map((i) => {
                'name': i.name,
                'detected': i.detected,
                'severity': i.severity,
                'description': i.description,
              })
          .toList(),
      'recommendation': recommendation,
      'summary': summary,
      'timestamp': timestamp.toIso8601String(),
      'extracted_data': extractedData == null
          ? null
          : {
              'ocr_text': extractedData!.ocrText,
              'payment_info': {
                'contains_payment_info': extractedData!.paymentInfo.containsPaymentInfo,
                'extracted_amount': extractedData!.paymentInfo.extractedAmount,
                'extracted_date': extractedData!.paymentInfo.extractedDate,
                'extracted_id': extractedData!.paymentInfo.extractedId,
              },
            },
    };
  }
}

class DbSearchResult {
  final String id;
  final String type;
  final String value;
  final String category;
  final String status;
  final int reportCount;
  final String description;

  const DbSearchResult({
    required this.id,
    required this.type,
    required this.value,
    required this.category,
    required this.status,
    required this.reportCount,
    required this.description,
  });

  factory DbSearchResult.fromJson(Map<String, dynamic> json) {
    return DbSearchResult(
      id: json['id'] as String,
      type: json['type'] as String,
      value: json['value'] as String,
      category: json['category'] as String,
      status: json['status'] as String,
      reportCount: json['report_count'] as int,
      description: json['description'] as String,
    );
  }
}
