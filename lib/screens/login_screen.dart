import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

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

  void _showResetPasswordDialog() {
    final resetController = TextEditingController(text: _emailController.text);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar Contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Te enviaremos un email para restablecer tu clave.', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: resetController,
              decoration: const InputDecoration(labelText: 'Tu Email', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              try {
                await Provider.of<AuthService>(context, listen: false).resetPassword(resetController.text);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email enviado con éxito.')));
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);

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
                const Icon(Icons.document_scanner, size: 80, color: Colors.deepPurpleAccent),
                const SizedBox(height: 16),
                const Text(
                  'FirmaFacil',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2),
                ),
                Text(_isLogin ? 'Ingresa a tu cuenta' : 'Regístrate gratis', style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 48),
                
                if (!_isLogin) ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre Completo',
                      prefixIcon: Icon(Icons.person),
                      filled: true,
                      fillColor: Colors.white10,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    filled: true,
                    fillColor: Colors.white10,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock),
                    filled: true,
                    fillColor: Colors.white10,
                  ),
                ),
                
                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showResetPasswordDialog,
                      child: const Text('¿Olvidaste tu clave?', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                      : Text(_isLogin ? 'INGRESAR' : 'CREAR CUENTA'),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin ? '¿No tienes cuenta? Regístrate' : '¿Ya tienes cuenta? Ingresa',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white12)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('O', style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(child: Divider(color: Colors.white12)),
                    ],
                  ),
                ),

                OutlinedButton.icon(
                  onPressed: () => auth.signInWithGoogle(),
                  icon: const Icon(Icons.login),
                  label: const Text('CONTINUAR CON GOOGLE'),
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
