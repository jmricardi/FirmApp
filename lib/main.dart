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
import 'services/network_service.dart';
import 'core/theme.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdfrx/pdfrx.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await pdfrxFlutterInitialize();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await RemoteConfigService().initialize();
  
  // Configurar escucha de links para referidos y verificación
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) async {
    // 1. Manejo de Referidos
    final ref = uri.queryParameters['ref'];
    if (ref != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_referral', ref);
      debugPrint('Código de referido capturado: $ref');
    }

    // 2. Manejo de Verificación de Email
    final oobCode = uri.queryParameters['oobCode'];
    final mode = uri.queryParameters['mode'];
    if (oobCode != null && mode == 'verifyEmail') {
      try {
        await FirebaseAuth.instance.applyActionCode(oobCode);
        debugPrint('Email verificado automáticamente desde App Link');
      } catch (e) {
        debugPrint('Error verificando email desde link: $e');
      }
    }
  });


  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => NetworkService()),
        ChangeNotifierProxyProvider2<AuthService, NetworkService, CreditService>(
          create: (_) => CreditService(null, null),
          update: (_, auth, network, previous) {
            if (previous != null && previous.uid == auth.currentUser?.uid) {
              previous.updateNetwork(network);
              return previous;
            }
            return CreditService(auth.currentUser?.uid, network);
          },
        ),
        ChangeNotifierProvider(create: (_) => AdService()),
        ChangeNotifierProvider(create: (_) => SettingsService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'FirmApp',
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
              final user = auth.currentUser;
              if (user != null) {
                // Prevenir flash del dashboard si el email no está verificado
                final isEmailPass = user.providerData.any((p) => p.providerId == 'password');
                if (isEmailPass && !user.emailVerified) {
                  return const LoginScreen();
                }
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
