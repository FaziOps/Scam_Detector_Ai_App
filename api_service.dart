// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';


class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ApiService {
  // Automatically picks the right host depending on the platform:
  //   iOS Simulator   → localhost   (loopback works directly)
  //   Android Emulator → 10.0.2.2  (special alias to host machine)
  //   Physical device → set BACKEND_URL in .env to your LAN IP
  static String get _backendUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8001';
    }
    // iOS Simulator, macOS, etc.
    return 'http://localhost:8001';
  }

  static String get _base => '$_backendUrl/api';
  static const _timeout = Duration(seconds: 30);
  static Map<String, String> get _headers => {'Content-Type': 'application/json'};

  static Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final url = Uri.parse('$_base$path');
    debugPrint('[API] POST $url');
    debugPrint('[API] body: ${jsonEncode(body).substring(0, (jsonEncode(body).length).clamp(0, 200))}');

    try {
      final response = await http
          .post(url, headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);

      debugPrint('[API] response status: ${response.statusCode}');
      debugPrint('[API] response body: ${response.body.substring(0, response.body.length.clamp(0, 300))}');

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 429) {
        throw ApiException(
          data['detail'] ?? 'Daily limit reached. Try again tomorrow.',
          statusCode: 429,
        );
      }
      if (response.statusCode >= 400) {
        throw ApiException(
          data['detail'] ?? 'Request failed (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      return data;
    } on SocketException catch (e) {
      debugPrint('[API] SocketException: $e');
      throw ApiException(
        'Cannot reach the backend server.\n\n'
        'Make sure:\n'
        '• Backend is running: uvicorn server:app --port 8001\n'
        '• iOS Simulator → use localhost:8001\n'
        '• Android Emulator → use 10.0.2.2:8001\n'
        '• Physical device → use your LAN IP:8001',
      );
    } on TimeoutException {
      throw ApiException('Request timed out. Is the backend running?');
    } on FormatException catch (e) {
      debugPrint('[API] FormatException: $e');
      throw ApiException('Unexpected response from server. Check backend logs.');
    } catch (e) {
      debugPrint('[API] Unexpected error: $e');
      rethrow;
    }
  }

  static Future<AnalysisResult> analyzeText(
      String text, String deviceId) async {
    final data = await _post('/analyze/text', {
      'text': text,
      'device_id': deviceId,
    });
    return AnalysisResult.fromJson(data);
  }

  static Future<AnalysisResult> analyzeUrl(
      String url, String deviceId) async {
    final data = await _post('/analyze/url', {
      'url': url,
      'device_id': deviceId,
    });
    return AnalysisResult.fromJson(data);
  }

  static Future<AnalysisResult> analyzeImage(
      String imageBase64, String deviceId) async {
    final data = await _post('/analyze/image', {
      'image_base64': imageBase64,
      'device_id': deviceId,
    });
    return AnalysisResult.fromJson(data);
  }

  static Future<void> submitReport({
    required String reportType,
    required String value,
    required String category,
    required String deviceId,
    String? description,
  }) async {
    await _post('/report/submit', {
      'report_type': reportType,
      'value': value,
      'category': category,
      'device_id': deviceId,
      if (description != null) 'description': description,
    });
  }

  static Future<List<DbSearchResult>> searchDatabase(
      String query, {String searchType = 'all'}) async {
    final data = await _post('/database/search', {
      'query': query,
      'search_type': searchType,
    });
    final results = data['results'] as List<dynamic>;
    return results
        .map((e) => DbSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<bool> checkHealth() async {
    try {
      final url = Uri.parse('$_base/health');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
