import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CreditService with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  int _credits = 0;
  String? _userId;

  int get credits => _credits;

  void updateUserId(String? uid) {
    _userId = uid;
    if (_userId != null) {
      _listenToCredits();
    }
  }

  void _listenToCredits() {
    _db.collection('users').doc(_userId).snapshots().listen((doc) {
      if (doc.exists) {
        _credits = doc.data()?['credits'] ?? 0;
        notifyListeners();
      }
    });
  }

  // Ahora usamos el Worker para sumar créditos también (más seguro y consistente)
  Future<bool> addCredit() async {
    return _callWorker('add');
  }

  Future<bool> useCredit() async {
    return _callWorker('deduct');
  }

  Future<bool> _callWorker(String action) async {
    if (_userId == null) return false;
    
    try {
      debugPrint('Llamando al Worker: $action para $_userId');
      final response = await http.post(
        Uri.parse('https://easyscan-credits-worker.jmricardi-3d1.workers.dev'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': _userId,
          'action': action,
          'secret': 'SuperEasyScan2024'
        }),
      );
      
      debugPrint('Worker Response Status: ${response.statusCode}');
      debugPrint('Worker Response Body: ${response.body}');
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error calling worker: $e');
      return false;
    }
  }
}
