import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../services/auth_service.dart';
import '../services/credit_service.dart';
import '../services/ad_service.dart';
import '../services/scanner_service.dart';
import 'faq_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scanner = ScannerService();
  List<File> _scannedDocs = [];
  File? _selectedFile;
  late StreamSubscription _intentDataStreamSubscription;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _initSharingIntent();
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  void _initSharingIntent() {
    // API ACTUALIZADA: Usar .instance
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedFiles(value);
      }
    }, onError: (err) {
      debugPrint("getIntentDataStream error: $err");
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedFiles(value);
      }
    });
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    for (var file in files) {
      await _scanner.importExternalFile(file.path);
    }
    _loadGallery();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archivo incorporado a Mis Documentos'))
      );
    }
  }

  Future<void> _initializeApp() async {
    _loadGallery();
    Provider.of<AdService>(context, listen: false).loadRewardedAd();

    final prefs = await SharedPreferences.getInstance();
    final hasSeenWelcome = prefs.getBool('has_seen_welcome') ?? false;

    if (!hasSeenWelcome) {
      if (mounted) {
        _showWelcomeDialog(prefs);
      }
    }
  }

  void _showWelcomeDialog(SharedPreferences prefs) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('¡Bienvenido a FirmaFacil!'),
        content: const Text(
          'Escanea tus documentos o impórtalos desde tu celular. '
          'Ahora puedes compartir archivos desde otras Apps directamente a FirmaFacil.'
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await prefs.setBool('has_seen_welcome', true);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Comenzar'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadGallery() async {
    final docs = await _scanner.getScannedDocuments();
    setState(() {
      _scannedDocs = docs;
      _selectedFile = null;
    });
  }

  Future<void> _handleImport() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'pdf', 'png', 'jpeg'],
    );

    if (result != null) {
      final path = result.files.single.path;
      if (path != null) {
        await _scanner.importExternalFile(path);
        _loadGallery();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Archivo importado con éxito'))
          );
        }
      }
    }
  }

  Future<void> _handleScan() async {
    final credits = Provider.of<CreditService>(context, listen: false);
    if (credits.credits <= 0) {
      _showNoCreditsSnackBar();
      return;
    }
    
    // Captura múltiple (ML Kit abrirá su interfaz de varias páginas)
    final paths = await _scanner.captureDocuments();
    if (paths != null && paths.isNotEmpty) {
      _showMultiPageResultDialog(paths);
      _loadGallery();
    }
  }

  void _showNoCreditsSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No tienes créditos suficientes. Mira un anuncio para ganar más.'))
    );
  }

  void _showMultiPageResultDialog(List<String> imagePaths) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool isSaved = false;

          return AlertDialog(
            title: Text(imagePaths.length > 1 ? 'Documento de ${imagePaths.length} hojas' : 'Documento Escaneado'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('¿Cómo deseas guardar el escaneo?', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: imagePaths.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(imagePaths[i]), height: 150, width: 100, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              if (!isSaved) ...[
                // Opción 1: Guardar cada hoja como JPG individual
                TextButton.icon(
                  icon: const Icon(Icons.collections),
                  onPressed: () async {
                    for (var path in imagePaths) {
                      await _scanner.exportToPublicGallery(path);
                    }
                    final success = await Provider.of<CreditService>(context, listen: false).useCredit();
                    if (success) {
                      setDialogState(() => isSaved = true);
                      _loadGallery();
                    }
                  },
                  label: Text(imagePaths.length > 1 ? 'JPGs sep. (-1)' : 'JPG (-1)'),
                ),
                // Opción 2: Todas las hojas en un solo PDF
                TextButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  onPressed: () async {
                    final pdfPath = await _scanner.saveAsPdf(imagePaths);
                    final success = await Provider.of<CreditService>(context, listen: false).useCredit();
                    if (success) {
                      setDialogState(() => isSaved = true);
                      _loadGallery();
                    }
                  },
                  label: const Text('PDF único (-1)'),
                ),
              ],
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
            ],
          );
        }
      ),
    );
  }

  void _showDeleteDialog(File file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Archivo'),
        content: const Text('¿Estás seguro de que quieres borrar este documento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              await _scanner.deleteFile(file.path);
              Navigator.pop(context);
              _loadGallery();
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(File file) {
    final controller = TextEditingController(text: file.path.split('/').last.split('.').first);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar Nombre'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nuevo nombre'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await _scanner.renameFile(file.path, controller.text);
                Navigator.pop(context);
                _loadGallery();
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleOCR(File file) async {
    final credits = Provider.of<CreditService>(context, listen: false);
    if (credits.credits <= 0) {
      _showNoCreditsSnackBar();
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final text = await _scanner.recognizeText(file.path);
      await credits.useCredit();
      await _scanner.saveAsText(text);
      if (mounted) {
        Navigator.pop(context);
        _showOCRResult(text);
        _loadGallery();
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _showOCRResult(String text) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Texto Extraído'),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final credits = Provider.of<CreditService>(context);
    final ads = Provider.of<AdService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FirmaFacil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FAQScreen())),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => auth.signOut()),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    color: const Color(0xFF252525),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Créditos', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text('${credits.credits}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: ads.isAdLoaded ? () => ads.showRewardedAd(
                        onRewardEarned: () async {
                          // Feedback visual inmediato
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Procesando tu crédito...'), duration: Duration(seconds: 1))
                          );
                          await credits.addCredit();
                        }
                      ) : ads.isConnecting ? null : () => ads.loadRewardedAd(),
                      icon: const Icon(Icons.play_circle_fill),
                      label: Text(ads.isAdLoaded ? '+1 Gratis' : 'Cargar'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent.withOpacity(0.2), foregroundColor: Colors.deepPurpleAccent, padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16)),
                    ),
                    const SizedBox(height: 8),
                    Text(ads.lastError, style: const TextStyle(fontSize: 8, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: _handleScan,
              icon: const Icon(Icons.document_scanner),
              label: const Text('NUEVO ESCANEO'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: Colors.deepPurpleAccent),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Mis Documentos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85,
              ),
              itemCount: _scannedDocs.length + 1,
              itemBuilder: (context, index) {
                if (index == _scannedDocs.length) {
                  return GestureDetector(
                    onTap: _handleImport,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        // CORRECCIÓN: BorderStyle.solid en lugar de dashed
                        border: Border.all(color: Colors.white24, style: BorderStyle.solid),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_to_photos, size: 40, color: Colors.white54),
                          SizedBox(height: 8),
                          Text('Importar JPG/PDF', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ),
                  );
                }

                final file = _scannedDocs[index];
                final isSelected = _selectedFile?.path == file.path;
                final isPdf = file.path.endsWith('.pdf');
                final isTxt = file.path.endsWith('.txt');
                
                // Cálculo de páginas (rápido)
                int pages = 1;
                if (isPdf) {
                  try {
                    final content = File(file.path).readAsStringSync(encoding: const Latin1Codec());
                    pages = RegExp(r'/Type\s*/Page\b').allMatches(content).length;
                    if (pages == 0) pages = 1;
                  } catch (_) { pages = 1; }
                }

                return GestureDetector(
                  onTap: () => setState(() => _selectedFile = isSelected ? null : file),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isSelected ? Colors.deepPurpleAccent : Colors.white12, width: isSelected ? 3 : 1),
                    ),
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: const Color(0xFF252525),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: isPdf 
                                  ? const Center(child: Icon(Icons.picture_as_pdf, size: 48, color: Colors.red))
                                  : isTxt
                                    ? const Center(child: Icon(Icons.description, size: 48, color: Colors.blue))
                                    : Image.file(file, fit: BoxFit.cover),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(file.path.split('/').last, style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                              ),
                            ],
                          ),
                          // Badge de cantidad de hojas
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.copy, size: 10, color: Colors.white70),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$pages',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selectedFile == null ? null : Container(
        height: 90, margin: const EdgeInsets.all(16), padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white12), boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)]),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _actionBtn(Icons.share, 'Compartir', Colors.blue, () => _scanner.shareFile(_selectedFile!.path)),
            _actionBtn(Icons.edit, 'Nombre', Colors.amber, () => _showRenameDialog(_selectedFile!)),
            _actionBtn(Icons.text_fields, 'OCR', Colors.green, () => _handleOCR(_selectedFile!)),
            _actionBtn(Icons.delete, 'Borrar', Colors.red, () => _showDeleteDialog(_selectedFile!)),
            const VerticalDivider(color: Colors.white10, indent: 20, endIndent: 20),
            IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => setState(() => _selectedFile = null)),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 9, color: Colors.white70))]),
    );
  }
}
