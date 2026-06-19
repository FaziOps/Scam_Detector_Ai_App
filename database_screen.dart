// lib/screens/database_screen.dart
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  final _controller = TextEditingController();
  List<DbSearchResult> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_controller.text.trim().length < 2) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final results = await ApiService.searchDatabase(_controller.text.trim());
      setState(() => _results = results);
    } catch (_) {
      setState(() => _results = []);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community Database')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search phone numbers, links, or message patterns reported by other users.',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 16),

            // Search bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style:
                        const TextStyle(color: AppColors.text, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'e.g. a phone number or domain',
                    ),
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _search,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Search',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.only(top: 24),
                child: CircularProgressIndicator(color: AppColors.primary),
              ))
            else if (_searched && _results.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(
                  child: Text(
                    "No reports found. That doesn't guarantee it's safe — always verify independently.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.5),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) => _ResultCard(result: _results[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final DbSearchResult result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final isConfirmed = result.status == 'confirmed_scam';

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
              Expanded(
                child: Text(
                  result.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isConfirmed ? AppColors.critical : AppColors.medium,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isConfirmed ? 'Confirmed' : 'Reported',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${result.type.toUpperCase()} • ${result.reportCount} report(s) • ${result.category}',
            style:
                const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          if (result.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              result.description,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
