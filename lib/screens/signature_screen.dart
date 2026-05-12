import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:signature/signature.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import '../services/signature_service.dart';
import '../services/scanner_service.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import '../services/credit_service.dart';
import '../services/signature_capture_service.dart';
import 'package:image_picker/image_picker.dart';
import 'signature_preview_screen.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final SignatureController _controller = SignatureController(
    penStrokeWidth: 2.2, // Un poco más fino para mayor elegancia
    penColor: const Color(0xFF000814), // Negro Tinta Real
    exportBackgroundColor: Colors.transparent,
  );

  final _sigService = SignatureService();
  final _captureService = SignatureCaptureService();
  final _scanner = ScannerService();
  bool _isProcessing = false;
  int _rotationTurns = 0;

  /// Ejecuta el flujo de guardado del canvas: Exportación -> Procesamiento -> Guardado -> Créditos.
  Future<void> _saveCanvas() async {
    if (_controller.isEmpty) return;

    final creditService = context.read<CreditService>();
    if (creditService.credits < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Créditos insuficientes (2 créditos)'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // 1. EXPORTACIÓN RESPONSIVA INTELIGENTE
      // Obtenemos el tamaño real del widget para una exportación nítida sin sobreconsumo
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      final double dpr = MediaQuery.of(context).devicePixelRatio;
      final double width = renderBox?.size.width ?? 800;
      final double height = renderBox?.size.height ?? 600;
      
      // Garantizamos alta densidad para PDF (3x DPR) sin agotar la RAM (máx 2400px)
      final int exportWidth = math.min((width * dpr * 3).round(), 2400);
      final int exportHeight = math.min((height * dpr * 3).round(), 2400);

      final bytes = await _controller.toPngBytes(
        width: exportWidth,
        height: exportHeight,
      );

      if (bytes == null) throw Exception("Error al exportar bytes del canvas");

      // 2. PROCESAMIENTO (Auto-crop optimizado en SignatureCaptureService)
      final processedBytes = await _captureService.processCanvasSignature(
        bytes,
        rotationTurns: _rotationTurns,
      );
      
      if (processedBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Firma no detectada o demasiado pequeña.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return;
      }

      // 3. GUARDADO PERSISTENTE
      await _captureService.saveSignature(processedBytes);

      // 4. FLUJO DE CRÉDITOS SEGURO (Solo al final del éxito)
      final success = await creditService.useCredit(
        amount: 2, 
        description: "Captura de Firma Digital",
      );

      if (success && mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Error en _saveCanvas: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar la firma: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final paths = await _scanner.captureDocuments(checkQuality: true, isSignature: true);
      if (paths == null || paths.isEmpty) return;

      if (!mounted) return;
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

        if (!mounted) return;
        final pathToProcess = cropped?.path ?? paths[0];
        final resultPath = await _sigService.processSignaturePhoto(pathToProcess, isFromCamera: true);

        if (resultPath != null && mounted) {
          final selectedPaths = await Navigator.push<List<String>>(
            context,
            MaterialPageRoute(
              builder: (_) => SignaturePreviewScreen(imagePath: resultPath),
            ),
          );

          if (selectedPaths != null && selectedPaths.isNotEmpty && mounted) {
            final credits = context.read<CreditService>();
            if (credits.credits < 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Créditos insuficientes (2 créditos)'), backgroundColor: Colors.redAccent),
              );
              return;
            }

            // Procesar guardado antes de cobrar
            for (var path in selectedPaths) {
              await _sigService.finalizeSignature(path);
            }
            await _sigService.cleanupTemporaries();

            // Cobrar solo tras éxito
            final success = await credits.useCredit(amount: 2, description: "Captura de Firma (Foto)");
            if (success && mounted) {
              Navigator.pop(context, true);
            }
          }
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains("QUALITY_INSUFFICIENT")) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('La imagen no es legible. Intenta con mejor iluminación.')),
              ],
            ),
            backgroundColor: Colors.orangeAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        debugPrint("Error processing signature: $e");
      }
    }
  }

  Future<void> _importPhoto() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      if (!mounted) return;
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

        if (!mounted) return;
        final pathToProcess = cropped?.path ?? pickedFile.path;
        final resultPath = await _sigService.processSignaturePhoto(pathToProcess, isFromCamera: false);

        if (resultPath != null && mounted) {
          final selectedPaths = await Navigator.push<List<String>>(
            context,
            MaterialPageRoute(
              builder: (_) => SignaturePreviewScreen(imagePath: resultPath),
            ),
          );

          if (selectedPaths != null && selectedPaths.isNotEmpty && mounted) {
            final credits = context.read<CreditService>();
            if (credits.credits < 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Créditos insuficientes (2 créditos)'), backgroundColor: Colors.redAccent),
              );
              return;
            }

            for (var path in selectedPaths) {
              await _sigService.finalizeSignature(path);
            }
            await _sigService.cleanupTemporaries();

            final success = await credits.useCredit(amount: 2, description: "Importación de Firma");
            if (success && mounted) {
              Navigator.pop(context, true);
            }
          }
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
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
              _buildInstructionHeader(lang),
              _buildSignatureCanvas(),
              _buildCanvasActions(lang),
              _buildExternalSourceActions(lang),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
          if (_isProcessing) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildInstructionHeader(String lang) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        LocalizationService.translate('sig_canvas_desc', lang),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _buildSignatureCanvas() {
    return Expanded(
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
    );
  }

  Widget _buildCanvasActions(String lang) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _rotationTurns = (_rotationTurns + 1) % 4),
            icon: const Icon(Icons.rotate_right, color: Colors.deepPurpleAccent),
            tooltip: 'Rotar firma final',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                _controller.clear();
                setState(() => _rotationTurns = 0);
              },
              icon: const Icon(Icons.clear),
              label: FittedBox(child: Text(LocalizationService.translate('sig_clear', lang))),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _saveCanvas,
              icon: const Icon(Icons.check),
              label: FittedBox(child: Text(LocalizationService.translate('sig_save', lang))),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExternalSourceActions(String lang) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera_alt),
              label: Text(LocalizationService.translate('sig_photo_btn', lang)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                backgroundColor: Colors.deepPurpleAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _importPhoto,
              icon: const Icon(Icons.image),
              label: Text(LocalizationService.translate('import_sig', lang)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
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
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
