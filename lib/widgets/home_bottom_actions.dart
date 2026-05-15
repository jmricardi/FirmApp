import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/credit_service.dart';
import 'help_balloon.dart';

class HomeBottomActions extends StatelessWidget {
  final Set<String> selectedFiles;
  final String lang;
  final VoidCallback onView;
  final VoidCallback onSign;
  final VoidCallback onFill;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onClear;

  const HomeBottomActions({
    super.key,
    required this.selectedFiles,
    required this.lang,
    required this.onView,
    required this.onSign,
    required this.onFill,
    required this.onShare,
    required this.onDelete,
    required this.onRename,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasSignature = selectedFiles.any((path) => path.contains('FRM_'));
    final credits = context.watch<CreditService>().credits;

    void handleCreditAction(VoidCallback action) {
      if (credits < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saldo insuficiente. Mira un anuncio o recomienda la app para continuar.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else {
        action();
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: const [
          BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, -2))
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _actionBtn(context, Icons.visibility, "Ver", onView,
                "Visualiza el contenido de los documentos seleccionados.",
                color: Colors.blue),
            if (!hasSignature)
              _actionBtn(
                  context,
                  Icons.history_edu,
                  "Firmar",
                  selectedFiles.length == 1 && selectedFiles.first.toLowerCase().endsWith('.pdf')
                      ? () => handleCreditAction(onSign)
                      : null,
                  "Abre el documento para firmarlo.",
                  color: credits < 1 ? Colors.grey : Colors.deepPurpleAccent),
            if (!hasSignature)
              _actionBtn(
                  context,
                  Icons.text_fields,
                  "Completar",
                  selectedFiles.length == 1 && selectedFiles.first.toLowerCase().endsWith('.pdf')
                      ? () => handleCreditAction(onFill)
                      : null,
                  "Añade texto y fechas al documento.",
                  color: credits < 1 ? Colors.grey : Colors.green),
            _actionBtn(context, Icons.share, "Compartir", onShare,
                "Comparte los archivos seleccionados.",
                color: Colors.teal),
            _actionBtn(context, Icons.delete_outline, "Eliminar", onDelete,
                "Borra los archivos seleccionados de forma permanente.",
                color: Colors.red),
            _actionBtn(context, Icons.edit, "Renombrar",
                selectedFiles.length == 1 ? onRename : null,
                "Permite cambiar el nombre del archivo seleccionado.",
                color: Colors.orange),
            _actionBtn(context, Icons.close, "", onClear,
                "Anula la selección actual y cierra este menú.",
                color: Colors.blueGrey),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(
      BuildContext context, IconData icon, String label, VoidCallback? onTap, String helpText,
      {Color color = Colors.deepPurpleAccent}) {
    final isHelpModeEnabled = context.watch<SettingsService>().isHelpModeEnabled;
    return HelpBalloon(
      message: helpText,
      isEnabled: isHelpModeEnabled,
      child: InkWell(
        onTap: isHelpModeEnabled ? null : onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onTap == null ? Colors.grey : color, size: 24),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(label,
                  style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: onTap == null ? Colors.grey : color)),
            ],
          ],
        ),
      ),
    );
  }
}
