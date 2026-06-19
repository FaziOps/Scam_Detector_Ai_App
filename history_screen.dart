// lib/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.history;

    if (history.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('History')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🕐', style: TextStyle(fontSize: 48)),
                SizedBox(height: 16),
                Text(
                  'No history yet',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text),
                ),
                SizedBox(height: 8),
                Text(
                  'Your past analyses will appear here. Go to the Analyze tab to check a message or link.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                      height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          TextButton(
            onPressed: () => _confirmClear(context, state),
            child: const Text('Clear All',
                style: TextStyle(color: AppColors.critical, fontSize: 14)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              '${history.length} past analysis${history.length != 1 ? 'es' : ''}, stored only on this device.',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
              itemCount: history.length,
              itemBuilder: (_, i) => _HistoryCard(
                result: history[i],
                onRemove: () => _confirmRemove(context, state, history[i].id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Clear History',
            style: TextStyle(color: AppColors.text)),
        content: const Text('Delete all past analyses? This cannot be undone.',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              state.clearHistory();
              Navigator.pop(context);
            },
            child: const Text('Clear All',
                style: TextStyle(color: AppColors.critical)),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, AppState state, String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remove Entry',
            style: TextStyle(color: AppColors.text)),
        content: const Text('Remove this analysis from history?',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              state.removeFromHistory(id);
              Navigator.pop(context);
            },
            child: const Text('Remove',
                style: TextStyle(color: AppColors.critical)),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final AnalysisResult result;
  final VoidCallback onRemove;
  const _HistoryCard({required this.result, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final rColor = riskColor(result.riskLevel);
    final dateStr = DateFormat('MMM d, y • h:mm a').format(result.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: rColor, width: 2),
                ),
                child: Center(
                  child: Text(
                    '${result.scamScore}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: rColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.riskLevel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: rColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${result.analysisType.toUpperCase()} · $dateStr',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close,
                    color: AppColors.textMuted, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            '${result.indicators.length} indicator(s) detected',
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
