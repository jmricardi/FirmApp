import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/credit_service.dart';
import 'services/ad_service.dart';
import 'services/settings_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/terms_screen.dart';
import 'screens/faq_screen.dart';
import 'services/remote_config_service.dart';
import 'core/theme.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await pdfrxFlutterInitialize();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await RemoteConfigService().initialize();
  
  // Configurar escucha de links para referidos
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) async {
    final ref = uri.queryParameters['ref'];
    if (ref != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_referral', ref);
      debugPrint('Código de referido capturado: $ref');
    }
  });

  // Chequear Referrer de Instalación (Google Play)
  if (Platform.isAndroid) {
    _checkInstallReferrer();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, CreditService>(
          create: (_) => CreditService(null),
          update: (_, auth, previous) => CreditService(auth.currentUser?.uid),
        ),
        ChangeNotifierProvider(create: (_) => AdService()),
        ChangeNotifierProvider(create: (_) => SettingsService()),
      ],
      child: const FirmaFacilApp(),
    ),
  );
}

class FirmaFacilApp extends StatelessWidget {
  const FirmaFacilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'FirmaFacil',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: settings.themeMode,
          routes: {
            '/settings': (context) => const SettingsScreen(),
            '/terms': (context) => const TermsScreen(),
            '/faq': (context) => const FAQScreen(),
          },
          home: Consumer<AuthService>(
            builder: (context, auth, _) {
              if (auth.currentUser != null) {
                return const HomeScreen();
              }
              return const LoginScreen();
            },
          ),
        );
      },
    );
  }
}

Future<void> _checkInstallReferrer() async {
  try {
    ReferrerDetails details = await AndroidPlayInstallReferrer.installReferrer;
    if (details.installReferrer != null) {
      // El formato suele ser: ref=ABC&utm_source=...
      final String? referrer = details.installReferrer;
      if (referrer != null && referrer.contains('ref=')) {
        final String refCode = referrer.split('ref=')[1].split('&')[0];
        final prefs = await SharedPreferences.getInstance();
        
        // Solo guardamos si no tenemos uno ya capturado por link directo
        if (!prefs.containsKey('pending_referral')) {
          await prefs.setString('pending_referral', refCode);
          debugPrint('Código de referido (Google Play) capturado: $refCode');
        }
      }
    }
  } catch (e) {
    debugPrint('Error leyendo Install Referrer: $e');
  }
}
