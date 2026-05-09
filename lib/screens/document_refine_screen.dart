import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';

class DocumentRefineScreen extends StatefulWidget {
  final String imagePath;

  const DocumentRefineScreen({super.key, required this.imagePath});

  @override
  State<DocumentRefineScreen> createState() => _DocumentRefineScreenState();
}

class _DocumentRefineScreenState extends State<DocumentRefineScreen> {
  final TransformationController _controller = TransformationController();
  PdfPageFormat _selectedFormat = PdfPageFormat.a4;
  double _tiltAngle = 0.0;
  bool _isProcessing = false;
  
  @override
  void initState() {
    super.initState();
    _suggestFormat();
  }

  Future<void> _suggestFormat() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return;

      final double imgW = image.width.toDouble();
      final double imgH = image.height.toDouble();
      // Usamos siempre la proporción Lado Corto / Lado Largo para evitar errores por rotación
      final double ar = (imgW < imgH) ? (imgW / imgH) : (imgH / imgW);

      final double a4AR = PdfPageFormat.a4.width / PdfPageFormat.a4.height;        // ~0.707
      final double letterAR = PdfPageFormat.letter.width / PdfPageFormat.letter.height; // ~0.772
      final double legalAR = PdfPageFormat.legal.width / PdfPageFormat.legal.height;   // ~0.607

      final diffs = {
        PdfPageFormat.a4: (ar - a4AR).abs(),
        PdfPageFormat.letter: (ar - letterAR).abs(),
        PdfPageFormat.legal: (ar - legalAR).abs(),
      };

      // Encontrar el formato con la diferencia más pequeña
      PdfPageFormat suggested = diffs.entries.reduce((a, b) => a.value < b.value ? a : b).key;

      if (mounted) {
        setState(() {
          _selectedFormat = suggested;
        });
      }
    } catch (e) {
      debugPrint("Error suggesting format: $e");
    }
  }

  // Variables para mapeo de recorte
  double _screenW = 0;
  double _screenH = 0;
  double _frameW = 0;
  double _frameH = 0;

  double get _targetAR => _selectedFormat.width / _selectedFormat.height;

  Future<void> _finish() async {
    setState(() => _isProcessing = true);
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return;

      final origW = image.width.toDouble();
      final origH = image.height.toDouble();

      // 1. Aplicar rotación de precisión (Fine Tilt)
      if (_tiltAngle != 0) {
        image = img.copyRotate(image, angle: _tiltAngle);
      }

      final rotW = image.width.toDouble();
      final rotH = image.height.toDouble();

      // 2. Mapeo inverso: Recortar la imagen exactamente como se ve en el marco
      if (_screenW > 0 && _screenH > 0 && _frameW > 0 && _frameH > 0) {
        // Escala usada por BoxFit.contain
        final fitScale = math.min(_screenW / origW, _screenH / origH);

        // Esquina superior izquierda de la imagen rotada en la pantalla
        final dx2 = _screenW / 2 - (rotW * fitScale) / 2;
        final dy2 = _screenH / 2 - (rotH * fitScale) / 2;

        // Invertir transformación del usuario
        final mInv = Matrix4.copy(_controller.value)..invert();

        final cropRect = Rect.fromCenter(
            center: Offset(_screenW / 2, _screenH / 2),
            width: _frameW,
            height: _frameH);

        // Mapear esquinas al espacio del InteractiveViewer
        final topLeftChild = MatrixUtils.transformPoint(mInv, cropRect.topLeft);
        final bottomRightChild = MatrixUtils.transformPoint(mInv, cropRect.bottomRight);

        // Traducir al espacio de píxeles de la imagen original
        int cropX = ((topLeftChild.dx - dx2) / fitScale).round();
        int cropY = ((topLeftChild.dy - dy2) / fitScale).round();
        int cropW = ((bottomRightChild.dx - topLeftChild.dx) / fitScale).round();
        int cropH = ((bottomRightChild.dy - topLeftChild.dy) / fitScale).round();

        // Límites de seguridad
        cropX = cropX.clamp(0, rotW.toInt() - 1);
        cropY = cropY.clamp(0, rotH.toInt() - 1);
        if (cropX + cropW > rotW.toInt()) cropW = rotW.toInt() - cropX;
        if (cropY + cropH > rotH.toInt()) cropH = rotH.toInt() - cropY;

        if (cropW > 0 && cropH > 0) {
          image = img.copyCrop(image, x: cropX, y: cropY, width: cropW, height: cropH);
        }
      }

      // Guardar la imagen procesada
      await File(widget.imagePath).writeAsBytes(img.encodeJpg(image, quality: 85));
      
      if (!mounted) return;
      Navigator.pop(context, {
        'path': widget.imagePath,
        'format': _selectedFormat,
      });
    } catch (e) {
      debugPrint("Error refining: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Ajustar Documento'),
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _screenW = constraints.maxWidth;
                _screenH = constraints.maxHeight;
                double margin = 40.0;
                double availableW = _screenW - margin;
                double availableH = _screenH - margin;
                
                if (availableW / availableH > _targetAR) {
                  _frameH = availableH;
                  _frameW = _frameH * _targetAR;
                } else {
                  _frameW = availableW;
                  _frameH = _frameW / _targetAR;
                }

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Imagen con Zoom/Pan e Inclinación
                    Positioned.fill(
                      child: InteractiveViewer(
                        transformationController: _controller,
                        minScale: 0.1,
                        maxScale: 10.0,
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        child: Center(
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            child: Transform.rotate(
                              angle: _tiltAngle * (math.pi / 180),
                              child: Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // Máscara de recorte (Overlay)
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: _CropOverlayPainter(
                          rect: Rect.fromCenter(
                            center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
                            width: _frameW,
                            height: _frameH,
                          ),
                        ),
                      ),
                    ),

                    if (_isProcessing)
                      const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ],
                );
              },
            ),
          ),
          
          // BARRA DE HERRAMIENTAS (Paso 5)
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              color: const Color(0xFF1A1A1A),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // CONTROL DE INCLINACIÓN (Grado a Grado)
                  Row(
                    children: [
                      const Icon(Icons.rotate_left, color: Colors.white54, size: 16),
                      Expanded(
                        child: Slider(
                          value: _tiltAngle,
                          min: -15,
                          max: 15,
                          divisions: 30,
                          activeColor: Colors.greenAccent,
                          onChanged: (val) => setState(() => _tiltAngle = val),
                        ),
                      ),
                      const Icon(Icons.rotate_right, color: Colors.white54, size: 16),
                      const SizedBox(width: 8),
                      Text('${_tiltAngle.toInt()}°', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Text('FORMATO DE SALIDA', 
                    style: TextStyle(color: Colors.white70, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _formatBtn('A4', PdfPageFormat.a4),
                      _formatBtn('CARTA', PdfPageFormat.letter),
                      _formatBtn('OFICIO', PdfPageFormat.legal),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _finish,
                    icon: const Icon(Icons.check_circle_outline, size: 22),
                    label: const Text("PROCESAR Y GUARDAR", 
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatBtn(String label, PdfPageFormat format) {
    bool isSelected = _selectedFormat == format;
    return GestureDetector(
      onTap: () => setState(() => _selectedFormat = format),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepPurpleAccent : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 1),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
        ],
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final Rect rect;
  const _CropOverlayPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final paint = Paint()..color = Colors.black.withOpacity(0.7);
    
    // Dibujar máscara oscura
    final path = Path()
      ..addRect(fullRect)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
    
    // Borde del marco
    final borderPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, borderPaint);

    // Esquinas táctiles (Visual)
    final cornerPaint = Paint()..color = Colors.greenAccent;
    double cs = 15; // corner size
    canvas.drawRect(Rect.fromLTWH(rect.left - 2, rect.top - 2, cs, 4), cornerPaint);
    canvas.drawRect(Rect.fromLTWH(rect.left - 2, rect.top - 2, 4, cs), cornerPaint);
    
    canvas.drawRect(Rect.fromLTWH(rect.right - cs + 2, rect.top - 2, cs, 4), cornerPaint);
    canvas.drawRect(Rect.fromLTWH(rect.right - 2, rect.top - 2, 4, cs), cornerPaint);

    canvas.drawRect(Rect.fromLTWH(rect.left - 2, rect.bottom - 2, cs, 4), cornerPaint);
    canvas.drawRect(Rect.fromLTWH(rect.left - 2, rect.bottom - cs + 2, 4, cs), cornerPaint);

    canvas.drawRect(Rect.fromLTWH(rect.right - cs + 2, rect.bottom - 2, cs, 4), cornerPaint);
    canvas.drawRect(Rect.fromLTWH(rect.right - 2, rect.bottom - cs + 2, 4, cs), cornerPaint);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) => rect != oldDelegate.rect;
}
