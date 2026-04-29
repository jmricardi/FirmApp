import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';

class AdService with ChangeNotifier {
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  bool _isConnecting = false;
  int _retryCount = 0;

  bool get isAdLoaded => _isAdLoaded;
  bool get isConnecting => _isConnecting;
  String _lastError = 'Ninguno';
  String get lastError => _lastError;

  // IDs del usuario
  final String _realAdUnitId = 'ca-app-pub-4820421076069967/7235190472';
  // ID de prueba de Google (siempre funciona para verificar integración)
  final String _testAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  void loadRewardedAd({bool useTestId = true}) {
    if (_isConnecting || _isAdLoaded) return;
    
    _isConnecting = true;
    notifyListeners();

    final adUnitId = useTestId ? _testAdUnitId : _realAdUnitId;

    debugPrint('AdMob: Iniciando carga de anuncio (${useTestId ? "MODO PRUEBA" : "MODO REAL"})...');

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
          _isConnecting = false;
          _retryCount = 0;
          debugPrint('AdMob: ¡ÉXITO! Anuncio cargado y listo.');
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          debugPrint('AdMob: ERROR al cargar (${error.code}). Mensaje: ${error.message}');
          _lastError = 'Error ${error.code}: ${error.message}';
          _isAdLoaded = false;
          _isConnecting = false;
          _rewardedAd = null;
          notifyListeners();
          
          // Lógica de reintento con backup de Test ID si el real falla
          _retryCount++;
          if (_retryCount >= 2 && !useTestId) {
            debugPrint('AdMob: Reintentando con Test ID...');
            loadRewardedAd(useTestId: true);
          }
        },
      ),
    );
  }

  void showRewardedAd({required Function onRewardEarned}) {
    if (_rewardedAd == null) {
      debugPrint('AdMob: No hay anuncio para mostrar, cargando uno nuevo...');
      loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('AdMob: Usuario cerró el anuncio.');
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdMob: Error al mostrar anuncio: ${error.message}');
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        loadRewardedAd();
      },
    );

    debugPrint('AdMob: Mostrando anuncio...');
    _rewardedAd!.show(onUserEarnedReward: (ad, reward) {
      debugPrint('AdMob: ¡Recompensa otorgada!');
      onRewardEarned();
    });
  }
}
