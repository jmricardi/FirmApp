import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleForgotPassword(AuthService auth, String lang) async {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa tu email')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await auth.resetPassword(_emailController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email de recuperación enviado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final lang = settings.localeCode;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark 
              ? [colorScheme.surface, Colors.black]
              : [colorScheme.surface, colorScheme.primaryContainer.withOpacity(0.3)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildHeader(colorScheme, lang),
                    const SizedBox(height: 48),
                    _buildForm(colorScheme, isDark, lang),
                    if (_isLogin)
                      _buildForgotPassword(lang),
                    const SizedBox(height: 24),
                    _buildSubmitButton(colorScheme, lang),
                    const SizedBox(height: 16),
                    _buildToggleLogin(colorScheme, lang),
                    _buildDivider(isDark, lang),
                    _buildSocialLogin(colorScheme, isDark, lang),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, String lang) {
    return Column(
      children: [
        Image.asset(
          'assets/icono.png', 
          height: 160,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.image_not_supported,
            size: 160,
            color: colorScheme.primary.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'FirmApp',
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _isLogin 
            ? LocalizationService.translate('login_enter', lang)
            : LocalizationService.translate('login_register', lang),
          style: GoogleFonts.outfit(color: Colors.grey, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildForm(ColorScheme colorScheme, bool isDark, String lang) {
    final fieldFillColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
    
    return Column(
      children: [
        if (!_isLogin) ...[
          TextFormField(
            controller: _nameController,
            style: TextStyle(color: colorScheme.onSurface),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: LocalizationService.translate('login_name', lang),
              prefixIcon: const Icon(Icons.person, color: Colors.grey),
              filled: true,
              fillColor: fieldFillColor,
              labelStyle: const TextStyle(color: Colors.grey),
            ),
            validator: (value) {
              if (!_isLogin && (value == null || value.trim().isEmpty)) {
                return 'Por favor, ingresa tu nombre';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
        ],
        TextFormField(
          controller: _emailController,
          style: TextStyle(color: colorScheme.onSurface),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: LocalizationService.translate('login_email', lang),
            prefixIcon: const Icon(Icons.email, color: Colors.grey),
            filled: true,
            fillColor: fieldFillColor,
            labelStyle: const TextStyle(color: Colors.grey),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Por favor, ingresa tu email';
            }
            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
              return 'Ingresa un email válido';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: TextStyle(color: colorScheme.onSurface),
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: LocalizationService.translate('login_password', lang),
            prefixIcon: const Icon(Icons.lock, color: Colors.grey),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: fieldFillColor,
            labelStyle: const TextStyle(color: Colors.grey),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Por favor, ingresa tu contraseña';
            }
            if (value.length < 6) {
              return 'La contraseña debe tener al menos 6 caracteres';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildForgotPassword(String lang) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => _handleForgotPassword(context.read<AuthService>(), lang),
        child: Text(
          LocalizationService.translate('login_forgot', lang),
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildSubmitButton(ColorScheme colorScheme, String lang) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : () async {
          if (!_formKey.currentState!.validate()) return;
          
          final auth = context.read<AuthService>();
          setState(() => _isLoading = true);
          try {
            if (_isLogin) {
              await auth.signInWithEmail(_emailController.text, _passwordController.text);
            } else {
              await auth.registerWithEmail(_emailController.text, _passwordController.text, _nameController.text);
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMessage(e))));
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _isLogin ? colorScheme.primary : colorScheme.tertiary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: _isLoading 
          ? CircularProgressIndicator(color: colorScheme.onPrimary)
          : Text(
              _isLogin 
                ? LocalizationService.translate('login_btn', lang)
                : LocalizationService.translate('login_create_btn', lang),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
      ),
    );
  }

  Widget _buildToggleLogin(ColorScheme colorScheme, String lang) {
    return TextButton(
      onPressed: () => setState(() => _isLogin = !_isLogin),
      child: Text(
        _isLogin 
          ? LocalizationService.translate('login_no_account', lang)
          : LocalizationService.translate('login_has_account', lang),
        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
      ),
    );
  }

  Widget _buildDivider(bool isDark, String lang) {
    final dividerColor = isDark ? Colors.white12 : Colors.black12;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Expanded(child: Divider(color: dividerColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              LocalizationService.translate('login_or', lang),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(child: Divider(color: dividerColor)),
        ],
      ),
    );
  }

  Widget _buildSocialLogin(ColorScheme colorScheme, bool isDark, String lang) {
    return OutlinedButton.icon(
      onPressed: _isLoading 
        ? null 
        : () async {
          setState(() => _isLoading = true);
          try {
            await context.read<AuthService>().signInWithGoogle();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMessage(e))));
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        },
      icon: const Icon(Icons.login),
      label: Text(LocalizationService.translate(_isLogin ? 'google_signin' : 'google_signup', lang)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _getFriendlyErrorMessage(dynamic e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('user-not-found')) return 'Usuario no encontrado';
    if (msg.contains('wrong-password')) return 'Contraseña incorrecta';
    if (msg.contains('invalid-email')) return 'Email inválido';
    if (msg.contains('email-already-in-use')) return 'El email ya está en uso';
    if (msg.contains('weak-password')) return 'La contraseña es muy débil';
    if (msg.contains('network-request-failed')) return 'Error de conexión';
    return e.toString();
  }
}
