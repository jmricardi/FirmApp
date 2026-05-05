import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final settings = Provider.of<SettingsService>(context);
    final lang = settings.localeCode;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A1A), Color(0xFF000000)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Image.asset('assets/logo.png', height: 140),
                const SizedBox(height: 16),
                Text(
                  LocalizationService.translate('app_name', lang),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2),
                ),
                Text(
                  _isLogin 
                    ? LocalizationService.translate('login_enter', lang)
                    : LocalizationService.translate('login_register', lang),
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 48),
                
                if (!_isLogin) ...[
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: LocalizationService.translate('login_name', lang),
                      prefixIcon: const Icon(Icons.person, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white10,
                      labelStyle: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: LocalizationService.translate('login_email', lang),
                    prefixIcon: const Icon(Icons.email, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.white10,
                    labelStyle: const TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: LocalizationService.translate('login_password', lang),
                    prefixIcon: const Icon(Icons.lock, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.white10,
                    labelStyle: const TextStyle(color: Colors.grey),
                  ),
                ),
                
                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {}, // Funcionalidad reset simplificada para demo
                      child: Text(
                        LocalizationService.translate('login_forgot', lang),
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ),

                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () async {
                      setState(() => _isLoading = true);
                      try {
                        if (_isLogin) {
                          await auth.signInWithEmail(_emailController.text, _passwordController.text);
                        } else {
                          await auth.registerWithEmail(_emailController.text, _passwordController.text, _nameController.text);
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                      } finally {
                        setState(() => _isLoading = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isLogin ? Colors.deepPurpleAccent : Colors.greenAccent.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isLogin 
                            ? LocalizationService.translate('login_btn', lang)
                            : LocalizationService.translate('login_create_btn', lang),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin 
                      ? LocalizationService.translate('login_no_account', lang)
                      : LocalizationService.translate('login_has_account', lang),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    children: [
                      const Expanded(child: Divider(color: Colors.white12)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          LocalizationService.translate('login_or', lang),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      const Expanded(child: Divider(color: Colors.white12)),
                    ],
                  ),
                ),

                OutlinedButton.icon(
                  onPressed: () => auth.signInWithGoogle(),
                  icon: const Icon(Icons.login),
                  label: Text(LocalizationService.translate(_isLogin ? 'google_signin' : 'google_signup', lang)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
