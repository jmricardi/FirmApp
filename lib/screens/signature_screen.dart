import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import '../services/signature_service.dart';
import '../services/scanner_service.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import '../services/credit_service.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'signature_preview_screen.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {


  final SignatureController _controller = SignatureController(
    penStrokeWidth: 2.5,
    penColor: const Color(0xFF000814),
    exportBackgroundColor: Colors.transparent,
  );

  final _sigService = SignatureService();
  final _scanner = ScannerService();
  bool _isProcessing = false;

  Future<void> _saveCanvas() async {
    if (_controller.isEmpty) return;

    final creditService = context.read<CreditService>();
    if (creditService.credits < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Créditos insuficientes (2 créditos)'), backgroundColor: Colors.redAccent)
        );
      }
      return;
    }

    setState(() => _isProcessing = true);
    final success = await creditService.useCredit(amount: 2, description: "Captura de Firma");
    if (!success) {
      setState(() => _isProcessing = false);
      return;
    }

    // PASO 3: Resolución de Alta Fidelidad (Anti-pixelado)
    // Forzamos un ancho de 2400px para que la firma siempre tenga alta densidad
    final bytes = await _controller.toPngBytes(
      width: 2400, 
      height: 1600,
    );
    
    if (bytes != null) {
      // PROCESO DE AUTO-CROP (Recorte Automático)
      final rawImage = img.decodePng(bytes);
      if (rawImage != null) {

        // Encontrar los límites del contenido (pixeles no transparentes)
        int minX = rawImage.width, maxX = 0, minY = rawImage.height, maxY = 0;
        bool found = false;

        for (int y = 0; y < rawImage.height; y++) {
          for (int x = 0; x < rawImage.width; x++) {
            final pixel = rawImage.getPixel(x, y);
            if (pixel.a > 0) { // En image 4.x, pixel.a es el canal alfa
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
              found = true;
            }
          }
        }

        if (found) {
          final padding = 40; // Aumentamos un poco el aire alrededor para que no se vea pegada
          minX = (minX - padding).clamp(0, rawImage.width);
          minY = (minY - padding).clamp(0, rawImage.height);
          maxX = (maxX + padding).clamp(0, rawImage.width);
          maxY = (maxY + padding).clamp(0, rawImage.height);

          final cropW = maxX - minX;
          final cropH = maxY - minY;

          // VALIDACIÓN DE RESOLUCIÓN MÍNIMA
          if (cropW < 200 || cropH < 100) {
            setState(() => _isProcessing = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Firma demasiado pequeña. Por favor, firma con un tamaño normal para asegurar la nitidez.'),
                  backgroundColor: Colors.orangeAccent,
                )
              );
            }
            return;
          }

          final croppedImage = img.copyCrop(rawImage, x: minX, y: minY, width: cropW, height: cropH);
          final croppedBytes = img.encodePng(croppedImage);
          

          await _scanner.saveCanvasSignature(croppedBytes);
        } else {
          await _scanner.saveCanvasSignature(bytes);
        }
      } else {
        await _scanner.saveCanvasSignature(bytes);
      }
      
      if (mounted) Navigator.pop(context, true);
    }
    setState(() => _isProcessing = false);
  }

  Future<void> _takePhoto() async {
    try {
      // Fuerza SIEMPRE el chequeo de calidad al capturar firma con cámara
      final paths = await _scanner.captureDocuments(checkQuality: true, isSignature: true);
      if (paths != null && paths.isNotEmpty) {
        setState(() => _isProcessing = true);
        
        try {
          final cropped = await ImageCropper().cropImage(
            sourcePath: paths[0],
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Ajustar Área de Firma',
                toolbarColor: Colors.black,
                toolbarWidgetColor: Colors.white,
                activeControlsWidgetColor: Colors.deepPurpleAccent,
                initAspectRatio: CropAspectRatioPreset.original,
                lockAspectRatio: false,
              ),
            ],
          );

          final pathToProcess = cropped?.path ?? paths[0];
          final resultPath = await _sigService.processSignaturePhoto(pathToProcess);
          
          if (resultPath != null && mounted) {
            final selectedPath = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => SignaturePreviewScreen(imagePath: resultPath),
              ),
            );
            
            if (selectedPath != null && mounted) {
              final credits = context.read<CreditService>();
              if (credits.credits < 2) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créditos insuficientes (2 créditos)'), backgroundColor: Colors.redAccent));
                return;
              }
              final success = await credits.useCredit(amount: 2, description: "Captura de Firma (Foto)");
              if (success) {
                await _sigService.finalizeSignature(selectedPath);
                Navigator.pop(context, true);
              }
            }
          }
        } finally {
          if (mounted) setState(() => _isProcessing = false);
        }
      }
    } catch (e) {
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
        debugPrint("Error processing signature: $e");
      }
    }
  }

  Future<void> _importPhoto() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      
      if (pickedFile != null) {
        setState(() => _isProcessing = true);
        
        try {
          final cropped = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Ajustar Área de Firma',
                toolbarColor: Colors.black,
                toolbarWidgetColor: Colors.white,
                activeControlsWidgetColor: Colors.deepPurpleAccent,
                initAspectRatio: CropAspectRatioPreset.original,
                lockAspectRatio: false,
              ),
            ],
          );

          final pathToProcess = cropped?.path ?? pickedFile.path;
          final resultPath = await _sigService.processSignaturePhoto(pathToProcess);
          
          if (resultPath != null && mounted) {
            final selectedPath = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => SignaturePreviewScreen(imagePath: resultPath),
              ),
            );
            
            if (selectedPath != null && mounted) {
              final credits = context.read<CreditService>();
              if (credits.credits < 2) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créditos insuficientes (2 créditos)'), backgroundColor: Colors.redAccent));
                return;
              }
              final success = await credits.useCredit(amount: 2, description: "Importación de Firma (Foto)");
              if (success) {
                await _sigService.finalizeSignature(selectedPath);
                Navigator.pop(context, true);
              }
            }
          }
        } finally {
          if (mounted) setState(() => _isProcessing = false);
        }
      }
    } catch (e) {
      debugPrint("Error importing signature: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final lang = settings.localeCode;

    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService.translate('sig_capture', lang))),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  LocalizationService.translate('sig_canvas_desc', lang),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.deepPurpleAccent, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Signature(
                      controller: _controller,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _controller.clear(),
                        icon: const Icon(Icons.clear),
                        label: Text(LocalizationService.translate('sig_clear', lang)),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveCanvas,
                        icon: const Icon(Icons.check),
                        label: Text(LocalizationService.translate('sig_save', lang)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _takePhoto,
                        icon: const Icon(Icons.camera_alt),
                        label: Text(LocalizationService.translate('sig_photo_btn', lang)),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: Colors.deepPurpleAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _importPhoto,
                        icon: const Icon(Icons.image),
                        label: Text(LocalizationService.translate('import_sig', lang)),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: Colors.deepPurple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.deepPurpleAccent),
                    SizedBox(height: 16),
                    Text('Procesando Firma...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('Extrayendo trazo y limpiando fondo', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
