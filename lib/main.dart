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
import 'core/theme.dart';

import 'package:pdfrx/pdfrx.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await pdfrxFlutterInitialize();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
