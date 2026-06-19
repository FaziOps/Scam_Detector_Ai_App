// lib/services/app_state.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

const _deviceIdKey = 'scam_detector_device_id';
const _historyKey  = 'scam_detector_history';
const _uuid        = Uuid();

class AppState extends ChangeNotifier {
  String? _deviceId;
  List<AnalysisResult> _history = [];
  bool _initialized = false;

  String? get deviceId     => _deviceId;
  List<AnalysisResult> get history => List.unmodifiable(_history);
  bool get initialized     => _initialized;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      String? id = prefs.getString(_deviceIdKey);
      if (id == null || id.isEmpty) {
        id = _uuid.v4();
        await prefs.setString(_deviceIdKey, id);
      }
      _deviceId = id;
      debugPrint('[AppState] deviceId = $_deviceId');

      final raw = prefs.getString(_historyKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final list = jsonDecode(raw) as List<dynamic>;
          _history = list
              .map((e) => AnalysisResult.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (e) {
          debugPrint('[AppState] history parse error: $e — clearing');
          _history = [];
        }
      }

      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[AppState] init error: $e');
      _deviceId = _uuid.v4(); // fallback in-memory id
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> addToHistory(AnalysisResult result) async {
    _history = [result, ..._history].take(100).toList();
    notifyListeners();
    await _saveHistory();
  }

  Future<void> removeFromHistory(String id) async {
    _history = _history.where((r) => r.id != id).toList();
    notifyListeners();
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    _history = [];
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyKey,
        jsonEncode(_history.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[AppState] save history error: $e');
    }
  }
}
