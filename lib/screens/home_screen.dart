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
  final Set<File> _selectedFiles = {};
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
        _scannedDocs = docs.where((f) => !f.path.contains('Firma_')).toList();
        _savedSignatures = docs.where((f) => f.path.contains('Firma_')).toList();
      });
    }
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

    final result = await showDialog<PdfPageFormat>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Normalizar PDF", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Selecciona el formato para estandarizar todas las páginas del PDF importado:", 
                style: TextStyle(fontSize: 13)),
              const SizedBox(height: 20),
              _pageSizeBtn("A4 (Estándar)", PdfPageFormat.a4, selected, (fmt) => setDialogState(() => selected = fmt)),
              _pageSizeBtn("CARTA (Letter)", PdfPageFormat.letter, selected, (fmt) => setDialogState(() => selected = fmt)),
              _pageSizeBtn("OFICIO (Legal)", PdfPageFormat.legal, selected, (fmt) => setDialogState(() => selected = fmt)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, selected), 
              child: const Text("Procesar (1 🪙)")
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      if (creditService.credits < 1) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créditos insuficientes'), backgroundColor: Colors.redAccent));
        return;
      }
      
      setState(() => _isProcessing = true);
      final success = await creditService.useCredit(amount: 1, description: "Importación de PDF Profesional");
      if (success) {
        await _scanner.importAndNormalizePdf(path, format: result);
        _loadGallery();
      }
      setState(() => _isProcessing = false);
    }
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

        // El costo ahora es fijo para PDF Profesional (1 crédito)
        if (creditService.credits < 1) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No tienes créditos suficientes (1 crédito)'), backgroundColor: Colors.redAccent)
            );
          }
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
          
          // Uso de créditos (Fijo 1 para importación profesional)
          if (creditService.credits < 1) {
             if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No tienes créditos suficientes (1 crédito)'), backgroundColor: Colors.redAccent)
              );
            }
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
    final credits = creditService.credits;
    final adService = context.watch<AdService>();

    // Lógica de Force Update
    if (creditService.forceUpdateVersion.isNotEmpty && creditService.localVersion.isNotEmpty) {
      if (_isVersionLower(creditService.localVersion, creditService.forceUpdateVersion)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showForceUpdateDialog(context, creditService.forceUpdateVersion));
      }
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', height: 32),
            const SizedBox(width: 10),
            Text(
              'FirmaFacil',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.pushNamed(context, '/settings')),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => context.read<AuthService>().signOut()),
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
                    Expanded(
                    child: GestureDetector(
                      onTap: _showHistorySheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.deepPurpleAccent.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.1)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.stars, color: Colors.amber, size: 24),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Tus Créditos', style: GoogleFonts.outfit(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 1)),
                                Text('$credits', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: adService.isAdLoaded ? () => adService.showRewardedAd(onRewardEarned: () => context.read<CreditService>().addCredit()) : null,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: adService.isAdLoaded ? Colors.green.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: adService.isAdLoaded ? Colors.green.withOpacity(0.2) : Colors.white10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              adService.isAdLoaded ? Icons.play_circle_fill : Icons.play_circle_outline, 
                              color: adService.isAdLoaded ? Colors.green : Colors.grey,
                              size: 26,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '+1 🪙', 
                              style: GoogleFonts.outfit(
                                fontSize: 14, 
                                fontWeight: FontWeight.bold,
                                color: adService.isAdLoaded ? Colors.green : Colors.grey
                              )
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _isHelpModeEnabled = !_isHelpModeEnabled),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _isHelpModeEnabled ? Colors.amber.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _isHelpModeEnabled ? Colors.amber : Colors.grey.withOpacity(0.5)),
                        ),
                        child: Icon(
                          _isHelpModeEnabled ? Icons.help : Icons.help_outline, 
                          color: _isHelpModeEnabled ? Colors.amber : Colors.grey,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
            Expanded(child: Column(children: [
              TabBar(
                controller: _tabController,
                tabs: [Tab(text: LocalizationService.translate('my_docs', lang)), Tab(text: LocalizationService.translate('signature', lang))], 
                indicatorColor: Colors.deepPurpleAccent, 
                labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold)
              ),
              Expanded(child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDocumentGrid(_scannedDocs, GridMode.import), 
                  _buildDocumentGrid(_savedSignatures, GridMode.signature)
                ]
              )),
            ])),
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
        final isSelected = _selectedFiles.contains(file);
        final isPdf = file.path.toLowerCase().endsWith('.pdf');
        
        String label = 'PDF';
        if (file.path.contains('A4_')) label = 'A4';
        else if (file.path.contains('LTR_')) label = 'CARTA';
        else if (file.path.contains('LGL_')) label = 'OFICIO';
        else if (file.path.contains('Firma_')) label = 'FIRMA';

        return GestureDetector(
          onTap: () => setState(() => isSelected ? _selectedFiles.remove(file) : _selectedFiles.add(file)),
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
                      file.path.split(Platform.pathSeparator).last.replaceFirst(RegExp(r'^(A4_|LTR_|LGL_)'), ''), 
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
        );
      },
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _handleCaptureAction,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.deepPurpleAccent.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2), style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.camera_enhance_outlined, size: 56, color: Colors.deepPurpleAccent.withOpacity(0.8)),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.add_circle, size: 24, color: Colors.deepPurpleAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Capturar\narchivo",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.deepPurpleAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddSignatureButton() {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const SignatureScreen()));
        if (result == true) _loadGallery();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orangeAccent.withOpacity(0.2), style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.gesture_rounded, size: 32, color: Colors.orangeAccent),
            const SizedBox(height: 8),
            Text(
              "Capturar\nfirma",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.orangeAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

   Widget _buildBottomActions(String lang) {
    return SafeArea(
      child: Container(
        height: 80, 
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), 
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, 
          borderRadius: BorderRadius.circular(24), 
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, spreadRadius: 2)]
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _actionBtn(Icons.visibility, LocalizationService.translate('view', lang), Colors.deepPurpleAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentViewerScreen(files: _selectedFiles.toList()))), debugId: "btn_view"),
                  _actionBtn(Icons.edit_document, LocalizationService.translate('sign', lang), Colors.orange, () async {
                    final file = _selectedFiles.first;
                    if (file.path.toLowerCase().endsWith('.pdf')) {
                      final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfSignatureScreen(pdfFile: file)));
                      if (res == true) { _selectedFiles.clear(); _loadGallery(); }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, convierte la imagen a PDF profesional primero.')));
                    }
                  }, debugId: "btn_sign"),
                  _actionBtn(Icons.share, LocalizationService.translate('share', lang), Colors.blue, () { for (var f in _selectedFiles) _scanner.shareFile(f.path); }, debugId: "btn_share"),
                  if (_selectedFiles.length == 1) ...[
                    _actionBtn(Icons.edit, LocalizationService.translate('rename', lang), Colors.amber, () => _showRenameDialog(_selectedFiles.first), debugId: "btn_rename"),
                  ],
                  _actionBtn(Icons.delete, LocalizationService.translate('delete', lang), Colors.redAccent, () => _showDeleteDialog(_selectedFiles.toList()), debugId: "btn_delete"),
                ],
              ),
            ),
          ),
          Container(
            height: 40,
            width: 1,
            color: Theme.of(context).dividerColor.withOpacity(0.2),
          ),
          IconButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            icon: const Icon(Icons.close_rounded, color: Colors.grey),
            onPressed: () => setState(() => _selectedFiles.clear()),
          ),
        ],
      ),
    ),
  );
}

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap, {String? debugId}) {
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, 
        children: [
          Icon(icon, color: color, size: 26), 
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w500))
        ]
      ),
    );
    return InkWell(onTap: onTap, child: content);
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
