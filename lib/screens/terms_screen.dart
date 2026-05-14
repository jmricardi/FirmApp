import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/localization_service.dart';
import '../widgets/custom_app_bar.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final lang = settings.localeCode;

    return Scaffold(
      appBar: const FirmAppAppBar(showActions: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(LocalizationService.translate('terms_s1_t', lang)),
            _bodyText(LocalizationService.translate('terms_s1_b', lang)),
            
            _sectionTitle(LocalizationService.translate('terms_s2_t', lang)),
            _bodyText(LocalizationService.translate('terms_s2_b', lang)),
            
            _sectionTitle(LocalizationService.translate('terms_s3_t', lang)),
            _bodyText(LocalizationService.translate('terms_s3_b', lang)),
            
            _sectionTitle(LocalizationService.translate('terms_s4_t', lang)),
            _bodyText(LocalizationService.translate('terms_s4_b', lang)),

            _sectionTitle(LocalizationService.translate('terms_s5_t', lang)),
            _bodyText(LocalizationService.translate('terms_s5_b', lang)),

            _sectionTitle(LocalizationService.translate('terms_s6_t', lang)),
            _bodyText(LocalizationService.translate('terms_s6_b', lang)),

            _sectionTitle(LocalizationService.translate('terms_s7_t', lang)),
            _bodyText(LocalizationService.translate('terms_s7_b', lang)),

            _sectionTitle(LocalizationService.translate('terms_s8_t', lang)),
            _bodyText(LocalizationService.translate('terms_s8_b', lang)),

            _sectionTitle(LocalizationService.translate('terms_s9_t', lang)),
            _bodyText(LocalizationService.translate('terms_s9_b', lang)),
            
            const SizedBox(height: 40),
            Center(
              child: Text(
                'Update: May 2026',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent),
      ),
    );
  }

  Widget _bodyText(String text) {
    return Text(
      text,
      textAlign: TextAlign.justify,
      style: const TextStyle(fontSize: 14, height: 1.5),
    );
  }
}
