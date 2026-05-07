import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class CreditService with ChangeNotifier {
  final String? _uid;
  int _credits = 0;
  bool _isLoading = false;

  final String _workerUrl = 'https://easyscan-credits-worker.jmricardi-3d1.workers.dev';
  final String _workerSecret = 'SuperEasyScan2024';
  List<dynamic> _history = [];
  String _localVersion = "";

  CreditService(this._uid) {
    if (_uid != null) {
      fetchCredits();
      fetchHistory();
    }
  }

  int get credits => _credits;
  String? get uid => _uid;
  bool get isLoading => _isLoading;
  List<dynamic> get history => _history;
  String get localVersion => _localVersion;

  Future<void> fetchHistory() async {
    if (_uid == null) return;
    try {
      final response = await http.get(
        Uri.parse('$_workerUrl?action=history&uid=$_uid'),
        headers: {'Authorization': _workerSecret},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _history = data['history'] ?? [];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetchHistory: $e');
    }
  }

  Future<void> fetchCredits() async {
    if (_uid == null) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      // Obtener versión local si aún no la tenemos
      if (_localVersion.isEmpty) {
        final packageInfo = await PackageInfo.fromPlatform();
        _localVersion = packageInfo.version;
      }

      final response = await http.get(
        Uri.parse('$_workerUrl?action=get&uid=$_uid&app_version=$_localVersion'),
        headers: {'Authorization': _workerSecret},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _credits = data['credits'] ?? 0;
        debugPrint('Créditos obtenidos: $_credits');
      } else {
        debugPrint('Error del servidor: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetchCredits: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addCredit() async {
    if (_uid == null) {
      debugPrint('Error: UID es nulo, no se puede añadir crédito');
      return;
    }
    
    try {
      debugPrint('Llamando al worker para añadir crédito para: $_uid');
      final response = await http.get(
        Uri.parse('$_workerUrl?action=add&uid=$_uid&desc=Recompensa%20de%20Publicidad'),
        headers: {'Authorization': _workerSecret},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('Servidor confirmó crédito. Refrescando...');
        await fetchCredits();
        await fetchHistory();
      } else {
        debugPrint('El servidor rechazó la suma de crédito: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error de red al añadir crédito: $e');
    }
  }

  Future<bool> useCredit({int amount = 1, String? description}) async {
    if (_uid == null || _credits < amount) return false;

    try {
      final descParam = description != null ? "&desc=${Uri.encodeComponent(description)}" : "";
      final response = await http.get(
        Uri.parse('$_workerUrl?action=use&uid=$_uid&amount=$amount$descParam'),
        headers: {'Authorization': _workerSecret},
      );

      if (response.statusCode == 200) {
        await fetchCredits();
        await fetchHistory();
        return true;
      }
    } catch (e) {
      debugPrint('Error useCredit: $e');
    }
    return false;
  }
}
