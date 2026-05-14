import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import 'help_balloon.dart';

class FirmAppAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onSettingsTap;
  final bool showSettings;
  final bool showActions;
  final List<Widget>? actions;

  const FirmAppAppBar({
    super.key,
    this.onSettingsTap,
    this.showSettings = true,
    this.showActions = true,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isHelpModeEnabled =
        context.watch<SettingsService>().isHelpModeEnabled;

    return AppBar(
      leading: (showActions && showSettings && (ModalRoute.of(context)?.isFirst ?? true))
          ? HelpBalloon(
              message: "Configura las preferencias de la aplicación y el idioma.",
              isEnabled: isHelpModeEnabled,
              balloonAlignment: Alignment.bottomRight,
              child: IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  if (onSettingsTap != null) {
                    onSettingsTap!();
                  }
                  Navigator.pushNamed(context, '/settings');
                },
              ),
            )
          : null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/icono.png', height: 32),
          const SizedBox(width: 10),
          Text(
            'FirmApp',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      actions: actions ??
          (showActions
              ? [
                  IconButton(
                    icon: Icon(
                      isHelpModeEnabled ? Icons.help : Icons.help_outline,
                      color: isHelpModeEnabled ? Colors.amber : null,
                    ),
                    onPressed: () =>
                        context.read<SettingsService>().toggleHelpMode(),
                  ),
                  HelpBalloon(
                    message: "Cierra tu sesión de forma segura.",
                    isEnabled: isHelpModeEnabled,
                    balloonAlignment: Alignment.bottomLeft,
                    child: IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () => context.read<AuthService>().signOut(),
                    ),
                  ),
                ]
              : null),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
