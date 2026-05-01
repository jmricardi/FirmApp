import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';

class AdService with ChangeNotifier {
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  bool _isConnecting = false;
  bool _sdkInitialized = false;
  String _lastError = 'Esperando...';
  
  // IDs CONFIGURADOS
  final String _realAdUnitId = 'ca-app-pub-4820421076069967/5299060763';
  final String _testAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  bool get isAdLoaded => _isAdLoaded;
  bool get isConnecting => _isConnecting;
  String get lastError => _lastError;

  AdService() {
    _initAdSystem();
  }

  Future<void> _initAdSystem() async {
    try {
      _lastError = 'Verificando consentimiento...';
      notifyListeners();
      
      await _handleConsent().timeout(const Duration(seconds: 5), onTimeout: () {});
      
      await MobileAds.instance.initialize();
      _sdkInitialized = true;
      
      // Iniciamos con el Real
      loadRewardedAd(useTestId: false); 
    } catch (e) {
      _lastError = 'Error inicialización: $e';
      notifyListeners();
    }
  }

  Future<void> _handleConsent() async {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        if (await ConsentInformation.instance.isConsentFormAvailable()) {
          _loadAndShowConsentForm(completer);
        } else {
          completer.complete();
        }
      },
      (error) => completer.complete(),
    );
    return completer.future;
  }

  void _loadAndShowConsentForm(Completer<void> completer) {
    ConsentForm.loadConsentForm(
      (consentForm) async {
        final status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          consentForm.show((formError) => completer.complete());
        } else {
          completer.complete();
        }
      },
      (formError) => completer.complete(),
    );
  }

  void loadRewardedAd({bool useTestId = false}) {
    if (_isAdLoaded || _isConnecting) return;
    
    _isConnecting = true;
    _lastError = useTestId ? 'Usando respaldo de prueba...' : 'Cargando real FirmaFacil...';
    notifyListeners();

    final adUnitId = useTestId ? _testAdUnitId : _realAdUnitId;

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
          _isConnecting = false;
          _lastError = useTestId ? 'Listo (MODO PRUEBA)' : '¡Anuncio Real Listo!';
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _isAdLoaded = false;
          _isConnecting = false;
          _rewardedAd = null;
          
          if (!useTestId) {
            // SI FALLÓ EL REAL: Mostrar error y saltar al de prueba
            _lastError = 'FirmaFacil Falló: ${error.message} (Cod:${error.code}). Cargando prueba...';
            notifyListeners();
            
            // Esperar 2 segundos para que el usuario vea el error y cargar el de prueba
            Future.delayed(const Duration(seconds: 2), () => loadRewardedAd(useTestId: true));
          } else {
            // SI FALLÓ EL DE PRUEBA TAMBIÉN
            _lastError = 'Sin anuncios disponibles.';
            notifyListeners();
          }
        },
      ),
    );
  }

  void showRewardedAd({required Function onRewardEarned}) {
    if (_rewardedAd == null) {
      loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        loadRewardedAd(useTestId: false); // Tras ver uno, intentar el real de nuevo
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        loadRewardedAd(useTestId: false);
      },
    );

    _rewardedAd!.show(onUserEarnedReward: (ad, reward) => onRewardEarned());
  }
}
