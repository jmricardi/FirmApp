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


  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, CreditService>(
          create: (_) => CreditService(null),
          update: (_, auth, previous) {
            // Si el usuario es el mismo, no recrear el servicio para no perder el estado
            if (previous != null && previous.uid == auth.currentUser?.uid) {
              return previous;
            }
            return CreditService(auth.currentUser?.uid);
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
