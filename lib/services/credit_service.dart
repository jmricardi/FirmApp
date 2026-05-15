import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'network_service.dart';

class CreditService with ChangeNotifier {
  final String? _uid;
  int _credits = -1; // -1 indica que los créditos aún no se han cargado
  bool _isLoading = false;
  final _uuid = const Uuid();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  NetworkService? _networkService;
  List<Map<String, dynamic>> _pendingSync = [];
  bool _isSyncing = false;

  final String _workerUrl =
      'https://firmapp-credits-worker.jmricardi-3d1.workers.dev';
  List<dynamic> _history = [];
  String _localVersion = "";

  CreditService(this._uid, this._networkService) {
    if (_uid != null) {
      _loadFromCache().then((_) {
        fetchCredits();
        fetchHistory();
        if (_networkService?.isOnline ?? false) {
          syncPendingTransactions();
        }
      });
    }
  }

  void updateNetwork(NetworkService? networkService) {
    if (_networkService == networkService) return;
    
    final wasOffline = _networkService?.isOnline == false;
    _networkService = networkService;
    
    if (wasOffline && (_networkService?.isOnline == true)) {
      syncPendingTransactions();
      fetchCredits();
    }
  }

  Future<void> _loadFromCache() async {
    if (_uid == null) return;
    try {
      final creditsStr = await _storage.read(key: 'credits_$_uid');
      if (creditsStr != null) {
        _credits = int.tryParse(creditsStr) ?? 0;
      }
      final historyStr = await _storage.read(key: 'history_$_uid');
      if (historyStr != null) {
        _history = jsonDecode(historyStr);
      }
      final pendingStr = await _storage.read(key: 'pending_sync_$_uid');
      if (pendingStr != null) {
        _pendingSync = List<Map<String, dynamic>>.from(jsonDecode(pendingStr));
      }
      if (creditsStr != null || historyStr != null || pendingStr != null) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading from cache: $e');
    }
  }

  Future<void> _saveToCache() async {
    if (_uid == null) return;
    try {
      await _storage.write(key: 'credits_$_uid', value: _credits.toString());
      await _storage.write(key: 'history_$_uid', value: jsonEncode(_history));
      await _storage.write(key: 'pending_sync_$_uid', value: jsonEncode(_pendingSync));
    } catch (e) {
      debugPrint('Error saving to cache: $e');
    }
  }

  int get credits => _credits;
  String? get uid => _uid;
  bool get isLoading => _isLoading;
  List<dynamic> get history => _history;
  String get localVersion => _localVersion;

  Future<Map<String, String>> _getHeaders({String? idempotencyKey}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User not authenticated");

    final token = await user.getIdToken();
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    if (idempotencyKey != null) {
      headers['X-Idempotency-Key'] = idempotencyKey;
    }

    return headers;
  }

  Future<void> fetchHistory() async {
    if (_uid == null) return;
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_workerUrl?action=history'),
        headers: headers,
      );
      debugPrint('History Response: ${response.statusCode} - ${response.body}');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          _history = decoded['data']['history'] ?? [];
          _saveToCache();
          notifyListeners();
        }
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
      if (_localVersion.isEmpty) {
        final packageInfo = await PackageInfo.fromPlatform();
        _localVersion = packageInfo.version;
      }

      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_workerUrl?action=get_credits&app_version=$_localVersion'),
        headers: headers,
      );

      debugPrint('Credits Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          _credits = decoded['data']['balance'] ?? 0;
          debugPrint('Créditos obtenidos: $_credits');
          _saveToCache();
        }
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

  Future<void> addCredit(
      {int amount = 1,
      String description = "Recompensa de Publicidad",
      String? customIdempotencyKey}) async {
    if (_uid == null) return;

    try {
      final idempotencyKey = customIdempotencyKey ??
          "add_${_uid}_${DateTime.now().millisecondsSinceEpoch}";
      final headers = await _getHeaders(idempotencyKey: idempotencyKey);

      final response = await http
          .post(
            Uri.parse(_workerUrl),
            headers: headers,
            body: jsonEncode({
              'action': 'add_credits',
              'amount': amount,
              'description': description,
              'idempotency_key': idempotencyKey,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          _credits = decoded['data']['balance'] ?? 0;
          await fetchHistory(); // Refrescar historial
          notifyListeners();
        }
      } else {
        debugPrint('Error en addCredit (Server): ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error en addCredit (Exception): $e');
    }
  }

  Future<bool> useCredit({int amount = 1, String? description}) async {
    if (_uid == null || _credits < amount) return false;

    final idempotencyKey = "use_${_uid}_${DateTime.now().millisecondsSinceEpoch}";
    final transactionDesc = description ?? "Uso de créditos";

    if (_networkService?.isOnline == false) {
      // Offline mode
      _credits -= amount;
      _pendingSync.add({
        'action': 'use_credits',
        'amount': amount,
        'description': transactionDesc,
        'idempotency_key': idempotencyKey,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _saveToCache();
      notifyListeners();
      return true;
    }

    try {
      final headers = await _getHeaders(idempotencyKey: idempotencyKey);
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: headers,
        body: jsonEncode({
          'action': 'use_credits',
          'amount': amount,
          'description': transactionDesc,
          'idempotency_key': idempotencyKey,
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          _credits = decoded['data']['balance'] ?? 0;
          await fetchHistory(); // Refrescar historial
          notifyListeners();
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error useCredit: $e');
    }
    return false;
  }

  Future<void> syncPendingTransactions() async {
    if (_uid == null || _pendingSync.isEmpty || _isSyncing) return;
    if (_networkService?.isOnline == false) return;

    _isSyncing = true;
    bool needsSave = false;

    try {
      final List<Map<String, dynamic>> toRemove = [];

      for (var tx in _pendingSync) {
        final headers = await _getHeaders(idempotencyKey: tx['idempotency_key']);
        
        try {
          final response = await http.post(
            Uri.parse(_workerUrl),
            headers: headers,
            body: jsonEncode({
              'action': tx['action'],
              'amount': tx['amount'],
              'description': tx['description'] + " (Offline Sync)",
              'idempotency_key': tx['idempotency_key'],
            }),
          );

          if (response.statusCode == 200 || response.statusCode == 409) {
            // Success or duplicate (conflict), remove from queue
            toRemove.add(tx);
            needsSave = true;
          }
        } catch (e) {
          debugPrint('Error syncing transaction: $e');
          break; // Stop syncing on network error
        }
      }

      if (toRemove.isNotEmpty) {
        _pendingSync.removeWhere((tx) => toRemove.contains(tx));
        await fetchCredits(); // Get accurate balance from server
        await fetchHistory();
      }
    } finally {
      if (needsSave) {
        await _saveToCache();
      }
      _isSyncing = false;
    }
  }

  Future<void> claimReferral(String referrerUid) async {
    if (_uid == null) return;
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_workerUrl?action=referral&ref=$referrerUid'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        await fetchCredits();
        await fetchHistory();
      }
    } catch (e) {
      debugPrint('Error claimReferral: $e');
    }
  }
}
