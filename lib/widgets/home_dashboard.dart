import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/credit_service.dart';
import '../services/ad_service.dart';
import 'help_balloon.dart';

class HomeDashboard extends StatelessWidget {
  final VoidCallback onHistoryTap;
  final VoidCallback onRecommend;

  const HomeDashboard({
    super.key,
    required this.onHistoryTap,
    required this.onRecommend,
  });

  @override
  Widget build(BuildContext context) {
    final isHelpModeEnabled = context.watch<SettingsService>().isHelpModeEnabled;
    final creditService = context.watch<CreditService>();
    final adService = context.watch<AdService>();
    final credits = creditService.credits;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bloque de Créditos (Principal) - REDUCIDO
            Expanded(
              flex: 2,
              child: HelpBalloon(
                message:
                    "Muestra tus créditos disponibles para firmar y procesar documentos.",
                isEnabled: isHelpModeEnabled,
                child: GestureDetector(
                  onTap: onHistoryTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepPurpleAccent.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.deepPurpleAccent.withOpacity(0.1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.stars, color: Colors.amber, size: 20),
                        const SizedBox(width: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('CREDITS',
                                style: GoogleFonts.outfit(
                                    fontSize: 8,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5)),
                            Text(credits == -1 ? '...' : '$credits',
                                style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Botón de Anuncio (+1) - AHORA EN SEGUNDA POSICIÓN
            Expanded(
              flex: 2,
              child: HelpBalloon(
                message: "Mira un anuncio corto para ganar 1 crédito gratis.",
                isEnabled: isHelpModeEnabled,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: adService.isAdLoaded
                        ? () async {
                            final earned = await adService.showRewardedAd();
                            if (earned) {
                              if (context.mounted) {
                                await context.read<CreditService>().addCredit();
                              }
                            }
                          }
                        : null,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: adService.isAdLoaded
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: adService.isAdLoaded
                                ? Colors.green.withOpacity(0.4)
                                : Colors.grey.withOpacity(0.2)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            adService.isAdLoaded
                                ? Icons.play_circle_fill
                                : Icons.play_circle_outline,
                            color: adService.isAdLoaded
                                ? Colors.green
                                : Colors.grey.withOpacity(0.4),
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(adService.isAdLoaded ? '+1' : '...',
                              style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: adService.isAdLoaded
                                      ? Colors.green
                                      : Colors.grey.withOpacity(0.4))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Botón de Recomendación (+5) - AHORA EN TERCERA POSICIÓN
            Expanded(
              flex: 2,
              child: HelpBalloon(
                message:
                    "Recomienda la app a un amigo y gana 5 créditos gratis.",
                isEnabled: isHelpModeEnabled,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onRecommend,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.blueAccent.withOpacity(0.2)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_add_alt_1,
                              color: Colors.blueAccent, size: 20),
                          const SizedBox(width: 4),
                          Text('+5',
                              style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
