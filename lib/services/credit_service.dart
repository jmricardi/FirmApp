import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CreditService with ChangeNotifier {
  final String? _uid;
  int _credits = 0;
  bool _isLoading = false;

  final String _workerUrl = 'https://easyscan-credits-worker.jmricardi-3d1.workers.dev';
  final String _workerSecret = 'SuperEasyScan2024';

  CreditService(this._uid) {
    if (_uid != null) {
      fetchCredits();
    }
  }

  int get credits => _credits;
  bool get isLoading => _isLoading;

  Future<void> fetchCredits() async {
    if (_uid == null) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$_workerUrl?action=get&uid=$_uid'),
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
        Uri.parse('$_workerUrl?action=add&uid=$_uid'),
        headers: {'Authorization': _workerSecret},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('Servidor confirmó crédito. Refrescando...');
        await fetchCredits();
      } else {
        debugPrint('El servidor rechazó la suma de crédito: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error de red al añadir crédito: $e');
    }
  }

  Future<bool> useCredit() async {
    if (_uid == null || _credits <= 0) return false;

    try {
      final response = await http.get(
        Uri.parse('$_workerUrl?action=use&uid=$_uid'),
        headers: {'Authorization': _workerSecret},
      );

      if (response.statusCode == 200) {
        await fetchCredits();
        return true;
      }
    } catch (e) {
      debugPrint('Error useCredit: $e');
    }
    return false;
  }
}
