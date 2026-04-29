import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'services/auth_service.dart';
import 'services/credit_service.dart';
import 'services/ad_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'core/theme.dart';
import 'firebase_options.dart'; // Este archivo lo genera FlutterFire CLI

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  MobileAds.instance.initialize();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, CreditService>(
          create: (_) => CreditService(),
          update: (_, auth, credit) => credit!..updateUserId(auth.currentUser?.uid),
        ),
        ChangeNotifierProvider(create: (_) => AdService()),
      ],
      child: const EasyScanApp(),
    ),
  );
}

class EasyScanApp extends StatelessWidget {
  const EasyScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyScan',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  _navigateToNext() async {
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.document_scanner_rounded, size: 100, color: Colors.deepPurpleAccent),
            const SizedBox(height: 24),
            const Text(
              'EasyScan',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(color: Colors.deepPurpleAccent),
          ],
        ),
      ),
    );
  }
}


class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    return authService.currentUser == null 
        ? const LoginScreen() 
        : const HomeScreen();
  }
}
