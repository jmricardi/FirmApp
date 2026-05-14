import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/settings_service.dart';
import '../services/localization_service.dart';
import '../services/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/help_balloon.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final lang = settings.localeCode;
    final isHelpModeEnabled = settings.isHelpModeEnabled;

    return Scaffold(
      appBar: const FirmAppAppBar(showSettings: false),
      body: ListView(
        children: [
          _buildSectionTitle(
              LocalizationService.translate('theme_title', lang)),
          HelpBalloon(
            message: "Cambia entre el modo claro y oscuro de la aplicación.",
            isEnabled: isHelpModeEnabled,
            balloonAlignment: Alignment.topRight,
            child: ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: Text(LocalizationService.translate('theme_dark', lang)),
              trailing: Switch(
                value: settings.themeMode == ThemeMode.dark,
                onChanged: (val) =>
                    settings.setThemeMode(val ? ThemeMode.dark : ThemeMode.light),
                activeThumbColor: Colors.deepPurpleAccent,
              ),
            ),
          ),
          _buildSectionTitle(
              LocalizationService.translate('language_label', lang)),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: const Text('Español'),
            trailing: Radio<String>(
              value: 'es',
              groupValue: lang,
              onChanged: (val) => settings.setLocale(val!),
              activeColor: Colors.deepPurpleAccent,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: const Text('English'),
            trailing: Radio<String>(
              value: 'en',
              groupValue: lang,
              onChanged: (val) => settings.setLocale(val!),
              activeColor: Colors.deepPurpleAccent,
            ),
          ),
          _buildSectionTitle(
              LocalizationService.translate('manual_crop', lang)),
          ListTile(
            leading: const Icon(Icons.crop_rounded),
            title: Text(LocalizationService.translate('manual_crop', lang)),
            subtitle: Text(LocalizationService.translate('crop_desc', lang)),
            trailing: Switch(
              value: settings.isManualCropEnabled,
              onChanged: (val) => settings.toggleManualCrop(val),
              activeThumbColor: Colors.deepPurpleAccent,
            ),
          ),
          _buildSectionTitle("Acerca de FirmApp"),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(LocalizationService.translate('terms', lang)),
            subtitle: const Text('Condiciones de uso del servicio',
                style: TextStyle(fontSize: 12)),
            onTap: () =>
                _launchURL('https://arandulabs.dev/FirmApp/terms.html'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Políticas de Privacidad'),
            subtitle: const Text('Cómo protegemos tus datos',
                style: TextStyle(fontSize: 12)),
            onTap: () =>
                _launchURL('https://arandulabs.dev/FirmApp/privacy.html'),
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded, color: Colors.blueAccent),
            title: const Text('Desarrollado por Arandu Labs'),
            subtitle: const Text('Visitar arandulabs.dev',
                style: TextStyle(fontSize: 12)),
            onTap: () => _launchURL('https://arandulabs.dev'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: Text(LocalizationService.translate('help', lang)),
            onTap: () => Navigator.pushNamed(context, '/faq'),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              onPressed: () => context.read<AuthService>().signOut(),
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              label: Text(LocalizationService.translate('logout', lang),
                  style: const TextStyle(color: Colors.redAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Error al abrir URL: $e");
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurpleAccent,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// Asegúrate de importar url_launcher al inicio del archivo
// import 'package:url_launcher/url_launcher.dart';
