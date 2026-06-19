// lib/screens/analyze_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/result_card.dart';

enum AnalyzeMode { text, url, image }

class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key});

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  AnalyzeMode _mode = AnalyzeMode.text;
  final _textController = TextEditingController();
  File? _imageFile;
  String? _imageBase64;
  bool _loading = false;
  AnalysisResult? _result;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _textController.clear();
      _imageFile = null;
      _imageBase64 = null;
      _result = null;
      _error = null;
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageFile = File(picked.path);
      _imageBase64 = base64Encode(bytes);
    });
  }

  Future<void> _handleAnalyze() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    final state = context.read<AppState>();
    final deviceId = state.deviceId;

    if (deviceId == null) {
      setState(() => _error = 'App not initialized yet. Please wait a moment and try again.');
      return;
    }

    if (_mode == AnalyzeMode.image && _imageBase64 == null) {
      setState(() => _error = 'Please select a screenshot first.');
      return;
    }
    if (_mode != AnalyzeMode.image && _textController.text.trim().length < 5) {
      setState(() => _error = 'Input too short. Please paste more content to analyze.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      AnalysisResult res;
      switch (_mode) {
        case AnalyzeMode.text:
          res = await ApiService.analyzeText(_textController.text.trim(), deviceId);
          break;
        case AnalyzeMode.url:
          res = await ApiService.analyzeUrl(_textController.text.trim(), deviceId);
          break;
        case AnalyzeMode.image:
          res = await ApiService.analyzeImage(_imageBase64!, deviceId);
          break;
      }

      if (!mounted) return;
      await state.addToHistory(res);
      setState(() {
        _result = res;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unexpected error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _handleReport() async {
    final state = context.read<AppState>();
    final deviceId = state.deviceId;
    if (deviceId == null || _result == null) return;

    final String value;
    if (_mode == AnalyzeMode.image) {
      final ocr = _result?.extractedData?.ocrText;
      if (ocr != null && ocr.isNotEmpty) {
        value = ocr.substring(0, ocr.length.clamp(0, 100));
      } else {
        value = 'screenshot content';
      }
    } else {
      value = _textController.text.trim();
    }

    final reportType = _mode == AnalyzeMode.url ? 'url' : 'pattern';

    try {
      await ApiService.submitReport(
        reportType: reportType,
        value: value,
        category: _result!.riskLevel,
        deviceId: deviceId,
        description: _result!.summary,
      );
      if (!mounted) return;
      _showAlert('Reported', 'Submitted for moderation review. Thank you.');
    } catch (e) {
      if (!mounted) return;
      _showAlert('Error', 'Could not submit: $e');
    }
  }

  void _showAlert(String title, String body) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: const TextStyle(color: AppColors.text)),
        content: Text(body, style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scam Detector AI'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a message, link, or upload a payment screenshot to check for scam indicators.',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 20),

            // ── Mode toggle ──────────────────────────────────────
            Row(
              children: AnalyzeMode.values.map((m) {
                final isActive = _mode == m;
                final label = m == AnalyzeMode.text
                    ? 'Message'
                    : m == AnalyzeMode.url
                        ? 'Link'
                        : 'Screenshot';
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _mode = m);
                        _reset();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isActive
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? Colors.white
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // ── Input ────────────────────────────────────────────
            if (_mode != AnalyzeMode.image)
              TextField(
                controller: _textController,
                maxLines: 6,
                minLines: 4,
                style: const TextStyle(color: AppColors.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _mode == AnalyzeMode.text
                      ? 'Paste SMS, WhatsApp message, or email text here...'
                      : 'Paste the URL here  e.g. https://suspicious-site.com',
                ),
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
              )
            else
              _ImagePickerWidget(
                imageFile: _imageFile,
                onTap: _pickImage,
              ),

            const SizedBox(height: 16),

            // ── Analyze button ───────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _handleAnalyze,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Analyze',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),

            // ── Error box ────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A1F1F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.critical),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: AppColors.critical, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Error',
                          style: TextStyle(
                            color: AppColors.critical,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.critical,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Result ──────────────────────────────────────────
            if (_result != null) ...[
              const SizedBox(height: 20),
              ResultCard(result: _result!),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleReport,
                  icon: const Icon(Icons.flag_outlined,
                      color: AppColors.high, size: 18),
                  label: const Text(
                    'Report this as a scam',
                    style: TextStyle(
                        color: AppColors.high,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.high),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 28),
            const Text(
              'Results are AI-generated risk estimates, not a legal or financial verdict. '
              'Always verify independently through official channels before acting.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontStyle: FontStyle.italic,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Image picker widget ──────────────────────────────────────────────────────
class _ImagePickerWidget extends StatelessWidget {
  final File? imageFile;
  final VoidCallback onTap;
  const _ImagePickerWidget({required this.imageFile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: imageFile != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(imageFile!, fit: BoxFit.contain),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: ElevatedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('Change'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.upload_file,
                      color: AppColors.textMuted, size: 36),
                  SizedBox(height: 10),
                  Text(
                    'Tap to select a payment screenshot',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'JPG, PNG from your photo library',
                    style: TextStyle(
                        color: AppColors.border, fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }
}
