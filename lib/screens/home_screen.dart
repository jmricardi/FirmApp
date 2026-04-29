import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showWelcomeDialog();
      _loadGallery();
      Provider.of<AdService>(context, listen: false).loadRewardedAd();
    });
  }

  void _showWelcomeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¡Bienvenido!'),
        content: const Text(
          'Gracias por confiar en EasyScan. '
          'Escanea tus documentos y obtén resultados profesionales en segundos.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Comenzar'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadGallery() async {
    final docs = await _scanner.getScannedDocuments();
    setState(() => _scannedDocs = docs);
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
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
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

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final credits = Provider.of<CreditService>(context);
    final ads = Provider.of<AdService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('EasyScan'),
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Créditos', style: TextStyle(color: Colors.grey)),
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
                ElevatedButton.icon(
                  onPressed: ads.isAdLoaded 
                    ? () => ads.showRewardedAd(onRewardEarned: () => credits.addCredit()) 
                    : ads.isConnecting ? null : () => ads.loadRewardedAd(),
                  icon: ads.isConnecting 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_circle_fill),
                  label: Text(ads.isAdLoaded ? '+1 Gratis' : 'Cargar Ad'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent.withOpacity(0.2),
                    foregroundColor: Colors.deepPurpleAccent,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: _handleScan,
              icon: const Icon(Icons.document_scanner),
              label: const Text('ESCANEAR DOCUMENTO'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
            ),
          ),

          if (!ads.isAdLoaded && ads.lastError != 'Ninguno')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Diagnóstico Ads: ${ads.lastError}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Mis Archivos Recientes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),

          Expanded(
            child: _scannedDocs.isEmpty 
              ? const Center(child: Text('No hay archivos recientes', style: TextStyle(color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: _scannedDocs.length,
                  itemBuilder: (context, index) {
                    final file = _scannedDocs[index];
                    final isPdf = file.path.endsWith('.pdf');
                    final isTxt = file.path.endsWith('.txt');
                    final fileName = file.path.split('/').last;
                    
                    return GestureDetector(
                      onTap: () => _scanner.shareFile(file.path),
                      onLongPress: () => _showRenameDialog(file),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: isPdf 
                                      ? const Center(child: Icon(Icons.picture_as_pdf, size: 48, color: Colors.red))
                                      : isTxt
                                        ? const Center(child: Icon(Icons.description, size: 48, color: Colors.blue))
                                        : Image.file(file, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: Text(
                                        fileName.split('.').last.toUpperCase(),
                                        style: const TextStyle(fontSize: 8, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      GestureDetector(
                                        onTap: () => _showDeleteDialog(file),
                                        child: const Icon(Icons.delete_outline, size: 28, color: Colors.redAccent),
                                      ),
                                      GestureDetector(
                                        onTap: () => _showRenameDialog(file),
                                        child: const Icon(Icons.edit_note, size: 28, color: Colors.grey),
                                      ),
                                      GestureDetector(
                                        onTap: () => _scanner.shareFile(file.path),
                                        child: const Icon(Icons.share, size: 28, color: Colors.deepPurpleAccent),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
