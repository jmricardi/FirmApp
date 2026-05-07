import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class RemoteConfigService {
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  Future<void> initialize() async {
    try {
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ));

      // Valores por defecto
      await _remoteConfig.setDefaults({
        'force_update_to': '1.3.0',
      });

      await fetchAndActivate();
    } catch (e) {
      debugPrint('Error inicializando Remote Config: $e');
    }
  }

  Future<void> fetchAndActivate() async {
    try {
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      debugPrint('Error al descargar Remote Config: $e');
    }
  }

  String get forceUpdateVersion => _remoteConfig.getString('force_update_to');
}
