import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart' as render;
import 'package:pdfrx_engine/pdfrx_engine.dart' as engine;
import '../services/scanner_service.dart';
import '../services/auth_service.dart';
import '../services/credit_service.dart';
import '../services/ad_service.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import 'signature_screen.dart';
import 'pdf_signature_screen.dart';
import 'document_viewer_screen.dart';
import 'document_refine_screen.dart';
import '../services/remote_config_service.dart';
import 'package:share_plus/share_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum GridMode { import, signature, none }

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _scanner = ScannerService();
  final _picker = ImagePicker();
  List<File> _scannedDocs = [];
  List<File> _savedSignatures = [];
  final Set<String> _selectedFiles = {};
  bool _isProcessing = false;
  final Map<String, int> _pageCountCache = {};
  final Map<String, ui.Image> _thumbnailCache = {}; 
  bool _isHelpModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // Limpiar selección al cambiar de pestaña (clic o swipe)
      if (!mounted) return;
      if (_selectedFiles.isNotEmpty) {
        setState(() => _selectedFiles.clear());
      }
    });
    _loadGallery();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGallery() async {
    final docs = await _scanner.getScannedDocuments();
    if (mounted) {
      setState(() {
        _scannedDocs = docs.where((f) {
          final name = f.path.split(Platform.pathSeparator).last;
          return !name.startsWith('FRM_');
        }).toList();
        _savedSignatures = docs.where((f) {
          final name = f.path.split(Platform.pathSeparator).last;
          return name.startsWith('FRM_');
        }).toList();
      });
    }
  }

  Future<void> _handleRecommend() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;

    final String inviteMsg = 
      "¡Hola! Te recomiendo FirmApp para escanear y firmar documentos PDF desde tu celular. "
      "Es súper rápida y profesional. Descárgala aquí: "
      "https://firmafacil.page.link/invite?ref=${user.uid}\n\n"
      "¡Si te registras con este link, ambos recibiremos 5 creditos de beneficios!";

    await Share.share(inviteMsg, subject: 'Te recomiendo FirmApp');
  }

  Future<int> _getPageCount(File file) async {
    if (!file.path.toLowerCase().endsWith('.pdf')) return 1;
    if (_pageCountCache.containsKey(file.path)) return _pageCountCache[file.path]!;
    
    try {
      final doc = await render.PdfDocument.openFile(file.path);
      final count = doc.pages.length;
      _pageCountCache[file.path] = count;
      return count;
    } catch (e) {
      return 1;
    }
  }

  Future<void> _showPdfImportDialog(String path) async {
    PdfPageFormat selected = PdfPageFormat.a4;
    final creditService = context.read<CreditService>();
    
    setState(() => _isProcessing = true);
    // Ajuste 6: Evaluación de medida más adecuada
    try {
      final doc = await render.PdfDocument.openFile(path);
      if (doc.pages.isNotEmpty) {
        final firstPage = doc.pages.first;
        final pw = firstPage.width;
        final ph = firstPage.height;
        
        // Comparación simple por área y proporción
        if (pw > 600 || ph > 900) selected = PdfPageFormat.legal;
        else if (pw > 550) selected = PdfPageFormat.letter;
        else selected = PdfPageFormat.a4;
      }
    } catch (e) {
      debugPrint("Error evaluando PDF: $e");
    }
    setState(() => _isProcessing = false);

    if (!mounted) return;

    final result = await showDialog<PdfPageFormat>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Normalizar PDF", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Selecciona el formato para estandarizar todas las páginas. Sugerimos el marcado por sus dimensiones originales:", 
                style: TextStyle(fontSize: 13)),
              const SizedBox(height: 20),
              _pageSizeBtn("A4 (Estándar)", PdfPageFormat.a4, selected, (fmt) => setDialogState(() => selected = fmt)),
              _pageSizeBtn("CARTA (Letter)", PdfPageFormat.letter, selected, (fmt) => setDialogState(() => selected = fmt)),
              _pageSizeBtn("OFICIO (Legal)", PdfPageFormat.legal, selected, (fmt) => setDialogState(() => selected = fmt)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20)
                ),
                icon: const Icon(Icons.auto_fix_high, size: 18),
                onPressed: () => Navigator.pop(context, selected), 
                label: const Text("PROCESAR (1 🪙)", style: TextStyle(fontWeight: FontWeight.bold))
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      // Ajuste 9: Verificar créditos con opción de anuncio
      final hasCredits = await _ensureCredits(1, "normalizar este PDF");
      if (!hasCredits) return;
      
      setState(() => _isProcessing = true);
      final success = await creditService.useCredit(amount: 1, description: "Importación de PDF Profesional");
      if (success) {
        await _scanner.importAndNormalizePdf(path, format: result);
        _loadGallery();
      }
      setState(() => _isProcessing = false);
    }
  }

  // Ajuste 9: Flujo de créditos insuficientes + Publicidad
  Future<bool> _ensureCredits(int required, String actionLabel) async {
    final creditService = context.read<CreditService>();
    final adService = context.read<AdService>();

    while (creditService.credits < required) {
      final res = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Consumer<CreditService>(
          builder: (context, cs, _) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.stars, color: Colors.amber),
                const SizedBox(width: 10),
                Text("Créditos Insuficientes", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Necesitas $required 🪙 para $actionLabel.", style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text("Tu saldo actual: ${cs.credits} 🪙", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text("¿Deseas ver un anuncio para ganar 1 🪙 y poder continuar?"),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Ahora no", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: adService.isAdLoaded ? () => Navigator.pop(context, true) : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(180, 48),
                  backgroundColor: Colors.deepPurpleAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Ver Anuncio (+1 🪙)", style: TextStyle(fontWeight: FontWeight.bold))
              ),
            ],
          ),
        ),
      );

      if (res == true) {
        final earned = await adService.showRewardedAd();
        if (earned) {
          // Ajuste: Await para asegurar que el saldo se actualice antes de la siguiente iteración
          await creditService.addCredit();
        } else {
          return false; // El usuario cerró el anuncio o falló
        }
      } else {
        return false; // El usuario canceló
      }
    }
    return true;
  }

  Future<void> _handleScan() async {
    final settings = context.read<SettingsService>();
    final lang = settings.localeCode;
    final creditService = context.read<CreditService>();

    try {
      final images = await _scanner.captureDocuments(
        checkQuality: settings.isQualityFilterEnabled
      );
      
      if (images != null && images.isNotEmpty) {
        setState(() => _isProcessing = true);
        
        List<String> refinedImages = [];
        PdfPageFormat? finalFormat;

        for (var imgPath in images) {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => DocumentRefineScreen(imagePath: imgPath)),
          );

          if (result != null && result is Map) {
            String p = result['path'];
            finalFormat = result['format'];
            refinedImages.add(p);
          } else {
            // Si el usuario cancela una página, cancelamos todo el documento
            await _scanner.clearTempScans();
            setState(() => _isProcessing = false);
            return;
          }
        }

        // Ajuste 9: Verificar créditos con opción de anuncio
        final hasCredits = await _ensureCredits(1, "guardar este documento");
        if (!hasCredits) {
          await _scanner.clearTempScans();
          setState(() => _isProcessing = false);
          return;
        }

        final success = await creditService.useCredit(amount: 1, description: "Escaneo de Documento");
        if (success) {
          await _scanner.saveAsPdf(refinedImages, format: finalFormat);
        }

        await _scanner.clearTempScans();
        setState(() => _isProcessing = false);
        _loadGallery();
      }
    } catch (e) {
      await _scanner.clearTempScans();
      if (e.toString().contains("QUALITY_INSUFFICIENT")) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('La imagen no era útil por no verse bien y fue descartada. Por favor, toma otra imagen con más iluminación y estabilidad.')),
                ],
              ),
              backgroundColor: Colors.orangeAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        debugPrint("Scan error: $e");
      }
    }
  }

  Future<void> _handleCaptureAction() async {
    setState(() => _selectedFiles.clear());
    final lang = context.read<SettingsService>().localeCode;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            ListTile(
              onTap: () { Navigator.pop(context); _handleScan(); },
              leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.deepPurpleAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.document_scanner, color: Colors.deepPurpleAccent)),
              title: const Text('Escanear Documento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Usar la cámara para digitalizar', style: TextStyle(color: Colors.grey, fontSize: 12)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white10)),
              tileColor: Colors.white.withOpacity(0.05),
            ),
            const SizedBox(height: 12),
            ListTile(
              onTap: () { Navigator.pop(context); _handleImport(); },
              leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.file_upload_outlined, color: Colors.blueAccent)),
              title: Text(LocalizationService.translate('import_file', lang), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Seleccionar PDF o imagen existente', style: TextStyle(color: Colors.grey, fontSize: 12)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white10)),
              tileColor: Colors.white.withOpacity(0.05),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImport() async {
    setState(() => _selectedFiles.clear());
    final creditService = context.read<CreditService>();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        
        if (path.toLowerCase().endsWith('.pdf')) {
          await _showPdfImportDialog(path);
        } else {
          setState(() => _isProcessing = true);
          List<String> refinedImages = []; // Declaración añadida
          PdfPageFormat? finalFormat; // Declaración añadida
          
          final settings = context.read<SettingsService>();
          if (settings.isQualityFilterEnabled) {
            final isGood = await _scanner.checkImageQuality(path);
            if (!isGood) {
              setState(() => _isProcessing = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.white),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('La imagen no era útil por no verse bien y fue descartada. Por favor, toma o selecciona otra imagen con más iluminación y estabilidad.')),
                      ],
                    ),
                    backgroundColor: Colors.orangeAccent,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              }
              return;
            }
          }

          // Refinamiento Manual para Importación
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => DocumentRefineScreen(imagePath: path)),
          );

          if (result != null && result is Map) {
            String p = result['path'];
            PdfPageFormat format = result['format'];
            refinedImages.add(p);
            finalFormat = format; // Usar el formato del refinamiento
          } else {
            setState(() => _isProcessing = false);
            return;
          }
          
          // Ajuste 9: Verificar créditos con opción de anuncio
          final hasCredits = await _ensureCredits(1, "importar esta imagen");
          if (!hasCredits) {
            setState(() => _isProcessing = false);
            return;
          }

          final success = await creditService.useCredit(amount: 1, description: "Importación de Imagen Profesional");
          if (success) {
            await _scanner.saveAsPdf(refinedImages, format: finalFormat);
          }
          
          _loadGallery();
          setState(() => _isProcessing = false);
        }
      }
    } catch (e) {
      debugPrint('Error en importación: $e');
    }
  }

  

  Widget _pageSizeBtn(String title, PdfPageFormat format, PdfPageFormat selected, Function(PdfPageFormat) onSelect) {
    bool isSelected = format == selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => onSelect(format),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.deepPurpleAccent.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? Colors.deepPurpleAccent : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, 
                   color: isSelected ? Colors.deepPurpleAccent : Colors.grey, size: 20),
              const SizedBox(width: 12),
              Text(title, style: GoogleFonts.outfit(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.deepPurpleAccent : Theme.of(context).colorScheme.onSurface,
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameDialog(File file) {
    String rawName = file.path.split(Platform.pathSeparator).last.split('.').first;
    String displayName = rawName;
    if (rawName.startsWith('A4_')) displayName = rawName.substring(3);
    else if (rawName.startsWith('LTR_')) displayName = rawName.substring(4);
    else if (rawName.startsWith('LGL_')) displayName = rawName.substring(4);
    else if (rawName.startsWith('Firma_')) displayName = rawName.substring(6);

    final controller = TextEditingController(text: displayName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Renombrar'),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              await _scanner.renameFile(file.path, controller.text);
              if (mounted) { Navigator.pop(context); _loadGallery(); setState(() => _selectedFiles.clear()); }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(List<File> files) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Eliminar'),
        content: Text('¿Deseas eliminar ${files.length} archivo(s)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              for (var f in files) { await _scanner.deleteFile(f.path); }
              if (mounted) { Navigator.pop(context); _loadGallery(); setState(() => _selectedFiles.clear()); }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showHistorySheet() {
    final creditService = context.read<CreditService>();
    creditService.fetchHistory(); 

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 15),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 25),
              Text("Historial de Movimientos", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              Expanded(
                child: Consumer<CreditService>(
                  builder: (context, svc, _) {
                    if (svc.history.isEmpty) {
                      return Center(child: Text("No hay movimientos registrados", style: TextStyle(color: Colors.grey)));
                    }
                    return ListView.builder(
                      itemCount: svc.history.length,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemBuilder: (context, index) {
                        final item = svc.history[index];
                        final amount = item['amount'] as int;
                        final isAdd = amount > 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: isAdd ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                child: Icon(isAdd ? Icons.add_circle_outline : Icons.remove_circle_outline, color: isAdd ? Colors.green : Colors.redAccent),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['description'] ?? "Servicio", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    Text(item['timestamp']?.toString() ?? "", style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                  ],
                                ),
                              ),
                              Text(
                                "${isAdd ? '+' : ''}$amount",
                                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: isAdd ? Colors.green : Colors.white),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsService>().localeCode;
    final creditService = context.watch<CreditService>();
    final adService = context.watch<AdService>();
    final credits = creditService.credits;

    // Ajuste 2: Mensaje de Bienvenida para nuevos usuarios
    if (!context.read<SettingsService>().hasSeenWelcome && credits == 5 && creditService.history.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted && !Navigator.of(context).canPop()) { 
          // Marcamos como visto antes de mostrar para evitar colisiones de build
          await context.read<SettingsService>().setWelcomeSeen();
          
          if (!mounted) return;

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text("¡Bienvenido a FirmApp!", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: const Text("Gracias por elegirnos para gestionar tus documentos. Te hemos regalado 5 créditos iniciales para que pruebes todas nuestras funciones.\n\n¡Esperamos que te sea de gran utilidad!"),
              actions: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(180, 50), // BOTÓN MÁS ANCHO
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(), 
                      child: const Text("Comenzar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                    ),
                  ),
                )
              ],
            ),
          );
          creditService.fetchHistory();
        }
      });
    }

    // Lógica de Force Update (Ahora vía Remote Config)
    final remoteConfig = RemoteConfigService();
    if (remoteConfig.forceUpdateVersion.isNotEmpty && creditService.localVersion.isNotEmpty) {
      if (_isVersionLower(creditService.localVersion, remoteConfig.forceUpdateVersion)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showForceUpdateDialog(context, remoteConfig.forceUpdateVersion));
      }
    }
    
    return Scaffold(
      appBar: AppBar(
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
        actions: [
          _HelpBalloon(
            message: "Configura las preferencias de la aplicación y el idioma.",
            isEnabled: _isHelpModeEnabled,
            balloonAlignment: Alignment.topLeft,
            child: IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () {
              setState(() => _selectedFiles.clear());
              Navigator.pushNamed(context, '/settings');
            }),
          ),
          _HelpBalloon(
            message: "Cierra tu sesión de forma segura.",
            isEnabled: _isHelpModeEnabled,
            balloonAlignment: Alignment.topLeft,
            child: IconButton(icon: const Icon(Icons.logout), onPressed: () => context.read<AuthService>().signOut()),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Bloque de Créditos (Principal) - REDUCIDO
                    Expanded(
                      flex: 2,
                      child: _HelpBalloon(
                        message: "Muestra tus créditos disponibles para firmar y procesar documentos.",
                        isEnabled: _isHelpModeEnabled,
                        child: GestureDetector(
                          onTap: _showHistorySheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.deepPurpleAccent.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.1)),
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
                                    Text('CREDITS', style: GoogleFonts.outfit(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                                    Text('$credits', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      child: _HelpBalloon(
                        message: "Mira un anuncio corto para ganar 1 crédito gratis.",
                        isEnabled: _isHelpModeEnabled,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: adService.isAdLoaded ? () async {
                              final earned = await adService.showRewardedAd();
                              if (earned) context.read<CreditService>().addCredit();
                            } : null,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: adService.isAdLoaded ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: adService.isAdLoaded ? Colors.green.withOpacity(0.4) : Colors.grey.withOpacity(0.2)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    adService.isAdLoaded ? Icons.play_circle_fill : Icons.play_circle_outline, 
                                    color: adService.isAdLoaded ? Colors.green : Colors.grey.withOpacity(0.4),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    adService.isAdLoaded ? '+1' : '...', 
                                    style: GoogleFonts.outfit(
                                      fontSize: 14, 
                                      fontWeight: FontWeight.bold,
                                      color: adService.isAdLoaded ? Colors.green : Colors.grey.withOpacity(0.4)
                                    )
                                  ),
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
                      child: _HelpBalloon(
                        message: "Recomienda la app a un amigo y gana 5 créditos gratis.",
                        isEnabled: _isHelpModeEnabled,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _handleRecommend,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.person_add_alt_1, color: Colors.blueAccent, size: 20),
                                  const SizedBox(width: 4),
                                  Text('+5', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 1,
                      child: _HelpBalloon(
                        message: "Activa/Desactiva el modo de ayuda interactiva.",
                        isEnabled: false,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _isHelpModeEnabled = !_isHelpModeEnabled),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _isHelpModeEnabled ? Colors.amber.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _isHelpModeEnabled ? Colors.amber : Colors.grey.withOpacity(0.5)),
                              ),
                              child: Icon(
                                _isHelpModeEnabled ? Icons.help : Icons.help_outline, 
                                color: _isHelpModeEnabled ? Colors.amber : Colors.grey,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  _HelpBalloon(
                    message: "Alterna entre tus documentos PDF y tus firmas guardadas.",
                    isEnabled: _isHelpModeEnabled,
                    balloonAlignment: Alignment.topLeft,
                    child: TabBar(
                      controller: _tabController,
                      tabs: [Tab(text: LocalizationService.translate('my_docs', lang)), Tab(text: LocalizationService.translate('signature', lang))], 
                      indicatorColor: Colors.deepPurpleAccent, 
                      labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold)
                    ),
                  ),
                  Expanded(child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDocumentGrid(_scannedDocs, GridMode.import), 
                      _buildDocumentGrid(_savedSignatures, GridMode.signature)
                    ]
                  )),
                ],
              ),
            ),
          ]),
          if (_isProcessing) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
      bottomNavigationBar: _selectedFiles.isEmpty ? null : _buildBottomActions(lang),
    );
  }

  Widget _buildDocumentGrid(List<File> docs, GridMode mode) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85),
      itemCount: docs.length + (mode != GridMode.none ? 1 : 0),
      itemBuilder: (context, index) {
        if (mode != GridMode.none && index == docs.length) {
          return mode == GridMode.import ? _buildAddButton() : _buildAddSignatureButton();
        }
        
        final file = docs[index];
        final isSelected = _selectedFiles.contains(file.path);
        final isPdf = file.path.toLowerCase().endsWith('.pdf');
        
        String label = 'PDF';
        if (file.path.contains('A4_')) label = 'A4';
        else if (file.path.contains('LTR_')) label = 'CARTA';
        else if (file.path.contains('LGL_')) label = 'OFICIO';
        else if (file.path.contains('FRM_') || file.path.contains('Firma_')) label = 'FIRMA';

        return _HelpBalloon(
          message: mode == GridMode.signature ? "Toca para gestionar esta firma guardada." : "Toca para seleccionar, mantén presionado para visualizar.",
          isEnabled: _isHelpModeEnabled,
          child: GestureDetector(
            onTap: () => setState(() => isSelected ? _selectedFiles.remove(file.path) : _selectedFiles.add(file.path)),
            onLongPress: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentViewerScreen(files: [file]))),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected ? Colors.deepPurpleAccent.withOpacity(0.1) : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? Colors.deepPurpleAccent : Colors.transparent, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(children: [
                  Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (mode == GridMode.signature) 
                              ? Colors.white 
                              : (isDark ? Colors.black26 : Colors.white24),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: isPdf 
                          ? _PdfThumbnail(file: file)
                          : (file.path.toLowerCase().endsWith('.jpg') || file.path.toLowerCase().endsWith('.png') 
                              ? Image.file(file, fit: (mode == GridMode.signature ? BoxFit.contain : BoxFit.cover)) 
                              : Icon(Icons.description, size: 40, color: Colors.blueAccent)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), 
                      child: Text(
                        file.path.split(Platform.pathSeparator).last.replaceFirst(RegExp(r'^(A4_|LTR_|LGL_|FRM_|Firma_)'), ''), 
                        maxLines: 1, 
                        overflow: TextOverflow.ellipsis, 
                        style: GoogleFonts.outfit(fontSize: 10, color: textColor)
                      )
                    ),
                  ])),
                  Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.deepPurpleAccent.withOpacity(0.9), borderRadius: BorderRadius.circular(6)), child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))),
                  if (isPdf)
                    Positioned(top: 8, right: 8, child: FutureBuilder<int>(
                      future: _getPageCount(file),
                      builder: (context, snapshot) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                        child: Text('${snapshot.data ?? "?"}', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    )),
                  Positioned(
                    top: 8, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isPdf ? Colors.redAccent : Colors.blueAccent).withOpacity(0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(isPdf ? "PDF" : "IMG", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _HelpBalloon(
      message: "Usa la cámara o importa un PDF para empezar a trabajar.",
      isEnabled: _isHelpModeEnabled,
      child: GestureDetector(
        onTap: _handleCaptureAction,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurpleAccent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.camera_enhance_rounded, size: 48, color: Colors.deepPurpleAccent.withOpacity(0.7)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(
                  "Capturar documento",
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddSignatureButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _HelpBalloon(
      message: "Dibuja una nueva firma para usar en tus documentos.",
      isEnabled: _isHelpModeEnabled,
      child: GestureDetector(
        onTap: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const SignatureScreen()));
          if (result == true) _loadGallery();
        },
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.orangeAccent.withOpacity(0.2), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.gesture_rounded, size: 48, color: Colors.orangeAccent.withOpacity(0.7)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(
                  "Capturar firma",
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions(String lang) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _actionBtn(Icons.visibility, "Ver", () {
              final filesToView = _selectedFiles.map((path) => File(path)).toList();
              Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentViewerScreen(files: filesToView)));
              setState(() => _selectedFiles.clear());
            }, "Visualiza el contenido de los documentos seleccionados.", color: Colors.blue),
            
            _actionBtn(Icons.history_edu, "Firmar", () {
              final filePath = _selectedFiles.first;
              if (_selectedFiles.length == 1 && filePath.toLowerCase().endsWith('.pdf')) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => PdfSignatureScreen(pdfFile: File(filePath))))
                  .then((result) {
                    if (result == true) _loadGallery();
                    setState(() => _selectedFiles.clear());
                  });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona exactamente un PDF para firmar')));
              }
            }, "Abre el editor para colocar una firma en el PDF seleccionado.", color: Colors.green),

            _actionBtn(Icons.delete, "Borrar", () {
              final filesToDelete = _selectedFiles.map((path) => File(path)).toList();
              _showDeleteDialog(filesToDelete);
            }, "Elimina permanentemente los archivos seleccionados.", color: Colors.redAccent),

            _actionBtn(Icons.share, "Compartir", () {
              for (var path in _selectedFiles) _scanner.shareFile(path);
              setState(() => _selectedFiles.clear());
            }, "Envía los archivos seleccionados a otras aplicaciones.", color: Colors.indigo),

            _actionBtn(Icons.edit, "Nombre", () {
              if (_selectedFiles.length == 1) {
                _showRenameDialog(File(_selectedFiles.first));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona solo un archivo para renombrar')));
              }
            }, "Permite cambiar el nombre del archivo seleccionado.", color: Colors.orange),

            _actionBtn(Icons.close, "", () => setState(() => _selectedFiles.clear()), "Anula la selección actual y cierra este menú.", color: Colors.blueGrey),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback? onTap, String helpText, {Color color = Colors.deepPurpleAccent}) {
    return _HelpBalloon(
      message: helpText,
      isEnabled: _isHelpModeEnabled,
      child: InkWell(
        onTap: _isHelpModeEnabled ? null : onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onTap == null ? Colors.grey : color, size: 24),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(label, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: onTap == null ? Colors.grey : color)),
            ],
          ],
        ),
      ),
    );
  }
  Widget _PdfThumbnail({required File file}) {
    if (_thumbnailCache.containsKey(file.path)) {
      return RawImage(image: _thumbnailCache[file.path]!, fit: BoxFit.cover);
    }

    return FutureBuilder<ui.Image?>(
      future: () async {
        try {
          final doc = await render.PdfDocument.openFile(file.path);
          if (doc.pages.isEmpty) return null;
          final page = doc.pages.first;
          final pdfImg = await page.render(
            width: 150, 
            height: 200,
            fullWidth: 150.0,
            fullHeight: 200.0,
          );
          final uiImg = await pdfImg?.createImage();
          if (uiImg != null) _thumbnailCache[file.path] = uiImg;
          return uiImg;
        } catch (e) {
          return null;
        }
      }(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData && snapshot.data != null) {
          return RawImage(
            image: snapshot.data!,
            fit: BoxFit.cover,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 1));
        }
        return const Center(child: Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 24));
      },
    );
  }

  bool _isVersionLower(String current, String target) {
    try {
      List<int> c = current.split('.').map((e) => int.parse(e)).toList();
      List<int> t = target.split('.').map((e) => int.parse(e)).toList();
      for (int i = 0; i < t.length; i++) {
        if (i >= c.length) return true;
        if (c[i] < t[i]) return true;
        if (c[i] > t[i]) return false;
      }
    } catch (e) {
      return current != target;
    }
    return false;
  }

  void _showForceUpdateDialog(BuildContext context, String newVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.system_update, color: Colors.amber),
              const SizedBox(width: 10),
              Text("Actualización Obligatoria", style: GoogleFonts.outfit(color: Colors.white)),
            ],
          ),
          content: Text(
            "Se requiere la versión $newVersion para continuar utilizando la aplicación. Por favor, actualiza desde la tienda oficial.",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Aquí podrías abrir la URL de la tienda
              },
              child: const Text("IR A LA TIENDA", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// Ajuste 3: Componente de Globo de Ayuda
class _HelpBalloon extends StatelessWidget {
  final Widget child;
  final String message;
  final bool isEnabled;
  final Alignment balloonAlignment;

  const _HelpBalloon({
    required this.child, 
    required this.message, 
    required this.isEnabled,
    this.balloonAlignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (isEnabled) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline, color: Colors.amber, size: 40),
                        const SizedBox(height: 16),
                        Text(message, textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 14)),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Entendido"))
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: balloonAlignment == Alignment.topLeft ? -4 : null,
            right: balloonAlignment == Alignment.topRight ? -4 : null,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.amber,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: const Icon(Icons.help, size: 8, color: Colors.black),
            ),
          ),
        ],
      ],
    );
  }
}
