import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdService with ChangeNotifier {
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  bool _isConnecting = false;
  bool _sdkInitialized = false;
  String _lastError = 'Esperando...';
  Timer? _loadTimer;
  
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
      _lastError = 'Iniciando...';
      notifyListeners();
      
      // Consentimiento con timeout
      try {
        await _handleConsent().timeout(const Duration(seconds: 4));
      } catch (_) {
        debugPrint('Consentimiento omitido');
      }
      
      await MobileAds.instance.initialize();
      _sdkInitialized = true;
      
      loadRewardedAd(useTestId: false); 
    } catch (e) {
      _lastError = 'Error: $e';
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
    // Si ya hay uno cargado o estamos en proceso, no duplicar (salvo que sea forzar prueba)
    if (_isAdLoaded || (_isConnecting && !useTestId)) return;
    
    _isConnecting = true;
    _lastError = useTestId ? 'Cargando prueba...' : 'Cargando real FirmApp...';
    notifyListeners();

    _loadTimer?.cancel();
    
    if (!useTestId) {
      _loadTimer = Timer(const Duration(seconds: 12), () {
        if (_isConnecting && !_isAdLoaded) {
          _isConnecting = false;
          loadRewardedAd(useTestId: true);
        }
      });
    }

    RewardedAd.load(
      adUnitId: useTestId ? _testAdUnitId : _realAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadTimer?.cancel();
          _rewardedAd = ad;
          _isAdLoaded = true;
          _isConnecting = false;
          _lastError = useTestId ? 'Prueba OK' : '¡Real OK!';
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _loadTimer?.cancel();
          _isAdLoaded = false;
          _isConnecting = false;
          _rewardedAd = null;
          
          if (!useTestId) {
            _lastError = 'FirmApp falló (${error.code})...';
            notifyListeners();
            Future.delayed(const Duration(seconds: 1), () => loadRewardedAd(useTestId: true));
          } else {
            _lastError = 'Sin anuncios.';
            notifyListeners();
          }
        },
      ),
    );
  }

  Future<bool> showRewardedAd() async {
    if (_rewardedAd == null) return false;
    
    final completer = Completer<bool>();
    bool earned = false;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      },
      onAdDismissedFullScreenContent: (ad) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        loadRewardedAd(useTestId: false);
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        loadRewardedAd(useTestId: false);
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    _rewardedAd!.show(onUserEarnedReward: (ad, reward) {
      earned = true;
    });

    return completer.future;
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _rewardedAd?.dispose();
    super.dispose();
  }
}
