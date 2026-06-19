// lib/widgets/result_card.dart
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class ResultCard extends StatelessWidget {
  final AnalysisResult result;

  const ResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final rColor = riskColor(result.riskLevel);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score row
          Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: rColor, width: 3),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${result.scamScore}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: rColor,
                      ),
                    ),
                    const Text(
                      '/ 100',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.riskLevel,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: rColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Confidence: ${(result.confidence * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${result.analysisType.toUpperCase()} ANALYSIS',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Recommendation box
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RECOMMENDATION',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  result.recommendation,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.text,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Summary
          Text(
            result.summary,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),

          // Indicators
          if (result.indicators.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Text(
              'Detected Indicators (${result.indicators.length})',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            ...result.indicators.map((ind) => _IndicatorRow(indicator: ind)),
          ],

          // Extracted screenshot data
          if (result.extractedData != null) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            const Text(
              'Extracted From Screenshot',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            if (result.extractedData!.paymentInfo.extractedAmount != null)
              _ExtractedRow(
                  label: 'Amount',
                  value: result.extractedData!.paymentInfo.extractedAmount!),
            if (result.extractedData!.paymentInfo.extractedDate != null)
              _ExtractedRow(
                  label: 'Date',
                  value: result.extractedData!.paymentInfo.extractedDate!),
            if (result.extractedData!.paymentInfo.extractedId != null)
              _ExtractedRow(
                  label: 'Reference ID',
                  value: result.extractedData!.paymentInfo.extractedId!),
            const SizedBox(height: 8),
            const Text(
              'This is a tamper-likelihood estimate based on extracted text, not proof of '
              'a genuine or fraudulent transaction. Always verify directly with your bank.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IndicatorRow extends StatelessWidget {
  final FraudIndicator indicator;
  const _IndicatorRow({required this.indicator});

  @override
  Widget build(BuildContext context) {
    final color = severityColor(indicator.severity);
    final label = indicator.name.replaceAll('_', ' ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label — ${indicator.severity}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  indicator.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtractedRow extends StatelessWidget {
  final String label;
  final String value;
  const _ExtractedRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 13, color: AppColors.text),
      ),
    );
  }
}
