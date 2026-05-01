import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    _initializeApp();
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
          'Escanea tus documentos y obtén resultados profesionales en segundos. '
          'Selecciona cualquier archivo para compartirlo, borrarlo o extraer su texto.'
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

  Future<void> _handleScan() async {
    final credits = Provider.of<CreditService>(context, listen: false);
    
    if (credits.credits <= 0) {
      _showNoCreditsSnackBar();
      return;
    }

    final path = await _scanner.captureDocument();
    if (path != null) {
      _showResultDialog(path);
      _loadGallery();
    }
  }

  void _showNoCreditsSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No tienes créditos suficientes. Mira un anuncio para ganar más.'))
    );
  }

  void _showResultDialog(String imagePath) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool isSaved = false;
          bool isOCRProcessing = false;
          String? extractedText;

          return AlertDialog(
            title: const Text('Documento Escaneado'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.file(File(imagePath), height: 250),
                  if (extractedText != null) ...[
                    const Divider(height: 32),
                    const Text('Texto Extraído:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black12,
                      width: double.infinity,
                      child: Text(extractedText!, style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              if (!isSaved) ...[
                TextButton.icon(
                  icon: const Icon(Icons.image),
                  onPressed: () async {
                    await _scanner.exportToPublicGallery(imagePath);
                    final success = await Provider.of<CreditService>(context, listen: false).useCredit();
                    if (success) {
                      setDialogState(() => isSaved = true);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado en Galería Pública')));
                    }
                  },
                  label: const Text('JPG (-1)'),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  onPressed: () async {
                    final pdfPath = await _scanner.saveAsPdf(imagePath);
                    final success = await Provider.of<CreditService>(context, listen: false).useCredit();
                    if (success) {
                      setDialogState(() => isSaved = true);
                      _scanner.shareFile(pdfPath);
                      _loadGallery();
                    }
                  },
                  label: const Text('PDF (-1)'),
                ),
              ],
              if (isSaved && extractedText == null)
                ElevatedButton.icon(
                  onPressed: isOCRProcessing ? null : () async {
                    final credits = Provider.of<CreditService>(context, listen: false);
                    if (credits.credits <= 0) {
                      _showNoCreditsSnackBar();
                      return;
                    }
                    
                    setDialogState(() => isOCRProcessing = true);
                    final text = await _scanner.recognizeText(imagePath);
                    final success = await credits.useCredit();
                    
                    if (success) {
                      await _scanner.saveAsText(text);
                      setDialogState(() {
                        extractedText = text;
                        isOCRProcessing = false;
                      });
                      _loadGallery();
                    } else {
                      setDialogState(() => isOCRProcessing = false);
                    }
                  },
                  icon: isOCRProcessing 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.text_fields),
                  label: const Text('Extraer Texto (+1 crédito)'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
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
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Créditos
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    color: const Color(0xFF252525), // Gris Slate para contraste
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Créditos Disponibles', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(
                            '${credits.credits}',
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: ads.isAdLoaded 
                        ? () => ads.showRewardedAd(onRewardEarned: () => credits.addCredit()) 
                        : ads.isConnecting ? null : () => ads.loadRewardedAd(),
                      icon: ads.isConnecting 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_circle_fill),
                      label: Text(ads.isAdLoaded ? '+1 Gratis' : 'Cargar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent.withOpacity(0.2),
                        foregroundColor: Colors.deepPurpleAccent,
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onLongPress: () => MobileAds.instance.openAdInspector((error) {
                        if (error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Inspector Error: ${error.message}'))
                          );
                        }
                      }),
                      child: Text(
                        ads.lastError,
                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
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
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                backgroundColor: Colors.deepPurpleAccent,
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Tus Documentos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),

          Expanded(
            child: _scannedDocs.isEmpty 
              ? const Center(child: Text('No hay archivos', style: TextStyle(color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _scannedDocs.length,
                  itemBuilder: (context, index) {
                    final file = _scannedDocs[index];
                    final isSelected = _selectedFile?.path == file.path;
                    final isPdf = file.path.endsWith('.pdf');
                    final isTxt = file.path.endsWith('.txt');
                    
                    return GestureDetector(
                      onTap: () => setState(() => _selectedFile = isSelected ? null : file),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? Colors.deepPurpleAccent : Colors.white12,
                            width: isSelected ? 3 : 1,
                          ),
                        ),
                        child: Card(
                          margin: EdgeInsets.zero,
                          color: const Color(0xFF252525),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
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
                                child: Text(
                                  file.path.split('/').last,
                                  style: const TextStyle(fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
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
      
      // BARRA DE COMANDOS INFERIOR
      bottomNavigationBar: _selectedFile == null ? null : Container(
        height: 90,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _actionBtn(Icons.share, 'Compartir', Colors.blue, () => _scanner.shareFile(_selectedFile!.path)),
            _actionBtn(Icons.edit, 'Nombre', Colors.amber, () => _showRenameDialog(_selectedFile!)),
            _actionBtn(Icons.text_fields, 'OCR', Colors.green, () => _handleOCR(_selectedFile!)),
            _actionBtn(Icons.delete, 'Borrar', Colors.red, () => _showDeleteDialog(_selectedFile!)),
            const VerticalDivider(color: Colors.white10, indent: 20, endIndent: 20),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => setState(() => _selectedFile = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white70)),
        ],
      ),
    );
  }
}
