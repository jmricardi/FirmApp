import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class NetworkService with ChangeNotifier {
  bool _isOnline = true;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool get isOnline => _isOnline;

  NetworkService() {
    _initConnectivity();
    _subscription = _connectivity.onConnectivityChanged.listen(_updateState);
  }

  Future<void> _initConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    await _updateState(results);
  }

  Future<void> _updateState(List<ConnectivityResult> results) async {
    if (results.contains(ConnectivityResult.none)) {
      _isOnline = false;
    } else {
      // Verificar internet real con un ping rápido
      _isOnline = await _checkRealInternet();
    }
    notifyListeners();
  }

  Future<bool> _checkRealInternet() async {
    try {
      // Intentamos contactar a Google o Cloudflare para asegurar salida a internet
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
