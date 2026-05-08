import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as render;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../services/signature_service.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import '../services/credit_service.dart';
import 'package:google_fonts/google_fonts.dart';

class SignatureStamp {
  final File signatureFile;
  final Offset positionInPoints; 
  final double widthInPoints;
  final double heightInPoints;
  final Color color;

  SignatureStamp({
    required this.signatureFile,
    required this.positionInPoints,
    required this.widthInPoints,
    required this.heightInPoints,
    required this.color,
  });
}

class PdfSignatureScreen extends StatefulWidget {
  final File pdfFile;

  const PdfSignatureScreen({super.key, required this.pdfFile});

  @override
  State<PdfSignatureScreen> createState() => _PdfSignatureScreenState();
}

class _PdfSignatureScreenState extends State<PdfSignatureScreen> {


  double? _lastLoggedScale;
  final _sigService = SignatureService();
  render.PdfDocument? _doc;
  int _totalPages = 0;
  int _currentPageIndex = 0;
  Uint8List? _pageImage;
  
  List<File> _availableSignatures = [];
  File? _selectedSignature;
  
  Offset _currentSigPosInPoints = const Offset(50, 50);
  double _currentSigWidthInPoints = 180; // Aumentado para mejor visibilidad inicial
  double _currentSigHeightInPoints = 100; // Aumentado para mejor visibilidad inicial
  Color _inkColor = Colors.black;
  double _selectedDpi = 250.0; // Default to Medium
  bool _isSaving = false;
  
  final Map<int, List<SignatureStamp>> _stamps = {};

  bool _isLoading = true;
  String _saveProgress = "";
  Size? _pdfPageSize; 
  
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    try {
      setState(() {
        _isLoading = true;
        _saveProgress = "Cargando documento...";
      });

      _availableSignatures = await _sigService.getSignatures();
      if (_availableSignatures.isNotEmpty) {
        _selectedSignature = _availableSignatures.first;
      }
      
      _doc = await render.PdfDocument.openFile(widget.pdfFile.path);
      _totalPages = _doc!.pages.length;
      if (_totalPages > 0) await _loadPage(0);
    } catch (e) {
      debugPrint("DEBUG ERROR: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPage(int index) async {
    if (_doc == null) return;
    try {
      final page = _doc!.pages[index];
      final int w = (page.width * 4).toInt();
      final int h = (page.height * 4).toInt();
      final pageImage = await page.render(
        width: w, 
        height: h,
        fullWidth: w.toDouble(),
        fullHeight: h.toDouble(),
      );
      
      if (pageImage != null) {
        final uiImage = await pageImage.createImage();
        final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        
        if (mounted) {
          setState(() {
            _pageImage = byteData!.buffer.asUint8List();
            _pdfPageSize = Size(page.width, page.height);
            _currentPageIndex = index;
            _transformationController.value = Matrix4.identity()..scale(1.15);
          });
          

        }
        pageImage.dispose();
        uiImage.dispose();
      }
    } catch (e) {
      debugPrint("DEBUG RENDER ERROR: $e");
    }
  }

  void _addStamp() {
    if (_selectedSignature == null) return;
    setState(() {
      _stamps.putIfAbsent(_currentPageIndex, () => []).add(
        SignatureStamp(
          signatureFile: _selectedSignature!,
          positionInPoints: _currentSigPosInPoints,
          widthInPoints: _currentSigWidthInPoints,
          heightInPoints: _currentSigHeightInPoints,
          color: _inkColor,
        ),
      );
      _selectedSignature = null; // DESELECCIONAR TRAS INCRUSTAR
    });
    debugPrint("DEBUG STAMP ADDED: Pos=${_currentSigPosInPoints.dx},${_currentSigPosInPoints.dy} | PageSize=${_pdfPageSize?.width}x${_pdfPageSize?.height}");
  }

  void _undoLastStamp() {
    setState(() {
      final stamps = _stamps[_currentPageIndex];
      if (stamps != null && stamps.isNotEmpty) {
        stamps.removeLast();
        if (stamps.isEmpty) _stamps.remove(_currentPageIndex);
      }
    });
  }

  Future<void> _saveFinalPdf() async {
    if (_doc == null || _pdfPageSize == null) return;
    
    final creditService = context.read<CreditService>();
    if (creditService.credits < 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Créditos insuficientes (1 crédito)'), backgroundColor: Colors.redAccent)
        );
      }
      return;
    }

    setState(() { _isSaving = true; });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.blueAccent),
            const SizedBox(height: 24),
            Text("Procesando Documento", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Calidad: ${_selectedDpi.toInt()} DPI", style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 16),
            const Text("Esto puede tardar unos segundos dependiendo del número de páginas.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
    );

    try {
      final success = await creditService.useCredit(amount: 1, description: "Firma de Documento PDF");
      if (!success) throw Exception("Error al procesar créditos");

      final pdf = pw.Document();
      
      for (int i = 0; i < _totalPages; i++) {
        final page = _doc!.pages[i];
        final double originalPageW = page.width;
        final double originalPageH = page.height;
        final double originalAR = originalPageW / originalPageH;
        
        // 1. SELECCIÓN DINÁMICA DE FORMATO (Respetar tamaño original)
        // Usamos las dimensiones originales de la página para evitar desplazamientos por estiramiento
        final double targetW = originalPageW; 
        final double targetH = originalPageH;
        final double targetAR = targetW / targetH;

        // 2. CÁLCULO DE DENSIDAD NATIVA (Sincronización Puntos vs Píxeles)
        // Usamos una escala dinámica basada en la selección del usuario
        final double targetDpi = _selectedDpi;
        final double nativeScale = targetDpi / 72.0; // Factor de conversión real
        
        final int canvasPixelsW = (targetW * nativeScale).toInt();
        final int canvasPixelsH = (targetH * nativeScale).toInt();

        // Renderizamos la página original ajustada a la densidad del lienzo final
        final pageRender = await page.render(
          width: canvasPixelsW, 
          height: canvasPixelsH,
          fullWidth: canvasPixelsW.toDouble(),
          fullHeight: canvasPixelsH.toDouble(),
        );
        final pageUiImg = await pageRender!.createImage();
        
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        
        // 3. RENDERIZADO 1:1 (Sincronizado con UI BoxFit.fill)
        canvas.drawImageRect(
          pageUiImg,
          Rect.fromLTWH(0, 0, canvasPixelsW.toDouble(), canvasPixelsH.toDouble()),
          Rect.fromLTWH(0, 0, canvasPixelsW.toDouble(), canvasPixelsH.toDouble()),
          Paint()..filterQuality = ui.FilterQuality.high
        );

        // 4. ESTAMPADO DE FIRMAS (Sincronización de Coordenadas)
        if (_stamps.containsKey(i)) {
          for (var stamp in _stamps[i]!) {
            final sigBytes = stamp.signatureFile.readAsBytesSync();
            final sigCodec = await ui.instantiateImageCodec(sigBytes);
            final sigFrame = await sigCodec.getNextFrame();
            final sigUiImg = sigFrame.image;
            
            // MAPEO CRÍTICO: De Puntos PDF (UI) a Píxeles de Canvas
            // Usamos el tamaño original de la página como base absoluta
            final double scaleX = canvasPixelsW / originalPageW;
            final double scaleY = canvasPixelsH / originalPageH;
            
            // Calculamos la posición en píxeles basándonos en la posición lógica capturada
            final double pxX = stamp.positionInPoints.dx * scaleX;
            final double pxY = stamp.positionInPoints.dy * scaleY; 
            final double pxW = stamp.widthInPoints * scaleX;
            final double pxH = stamp.heightInPoints * scaleY;
            
            debugPrint("DEBUG DRAW STAMP [$i]: LogicalPos=${stamp.positionInPoints} | CanvasPos=($pxX, $pxY) | Page=$originalPageW x $originalPageH");

            canvas.drawImageRect(
              sigUiImg,
              Rect.fromLTWH(0, 0, sigUiImg.width.toDouble(), sigUiImg.height.toDouble()),
              Rect.fromLTWH(pxX, pxY, pxW, pxH),
              Paint()
                ..filterQuality = ui.FilterQuality.high
                ..isAntiAlias = true
                ..colorFilter = ui.ColorFilter.mode(stamp.color, ui.BlendMode.srcIn)
            );
            sigUiImg.dispose();
          }
        }

        final finalImg = await recorder.endRecording().toImage(canvasPixelsW, canvasPixelsH);
        final finalBytes = await finalImg.toByteData(format: ui.ImageByteFormat.png);
        final pwImg = pw.MemoryImage(finalBytes!.buffer.asUint8List());

        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat(targetW, targetH, marginAll: 0),
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(
                pwImg, 
                width: targetW,  // MAPEO 1:1 DE PUNTOS (Fijamos tamaño físico)
                height: targetH, // MAPEO 1:1 DE PUNTOS
                fit: pw.BoxFit.fill
              ),
            );
          },
        ));


        pageRender.dispose();
        pageUiImg.dispose();
        finalImg.dispose();
      }
      
      final directory = await getApplicationDocumentsDirectory();
      final originalName = widget.pdfFile.path.split(Platform.pathSeparator).last.split('.').first;
      // Ajuste Nomenclatura (Problema 4): Usar prefijo FirmaFacil_ para que sea detectado por el ScannerService
      final fileName = 'FF_SIGNED_${originalName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outputFile = File('${directory.path}/scans/$fileName');
      if (!outputFile.parent.existsSync()) outputFile.parent.createSync();
      await outputFile.writeAsBytes(await pdf.save());
      
      if (mounted) {
        Navigator.pop(context); // Cerrar el diálogo de "Procesando Documento"
        Navigator.pop(context, true); // Volver al Home indicando que hubo cambios
      }
    } catch (e) {
      debugPrint("DEBUG SAVE ERROR: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.deepPurpleAccent),
            const SizedBox(height: 20),
            Text(_saveProgress, style: const TextStyle(color: Colors.white70)),
          ],
        )),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(title: const Text('Firmar Documento')),
      body: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            color: Colors.black,
            child: Row(children: [
              // Texto TINTA más compacto o removido si es necesario
              const Text('INK:', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _colorBtn(Colors.black), 
                      _colorBtn(const Color(0xFF00003F)), 
                      _colorBtn(const Color(0xFF0D47A1)), 
                      _colorBtn(Colors.red.shade700),
                      _colorBtn(Colors.green.shade700),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${_currentPageIndex + 1} / $_totalPages', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              IconButton(
                constraints: const BoxConstraints(maxWidth: 32),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_left, color: Colors.white, size: 20), 
                onPressed: _currentPageIndex > 0 ? () => _loadPage(_currentPageIndex - 1) : null
              ),
              IconButton(
                constraints: const BoxConstraints(maxWidth: 32),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_right, color: Colors.white, size: 20), 
                onPressed: _currentPageIndex < _totalPages - 1 ? () => _loadPage(_currentPageIndex + 1) : null
              ),
            ]),
          ),
          
          // Selector de Calidad (DPI)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                const Text('CALIDAD:', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                _qualityBtn("BAJA", 150.0),
                _qualityBtn("MEDIA", 250.0),
                _qualityBtn("ALTA", 350.0),
              ],
            ),
          ),

          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            if (_pdfPageSize == null) return const SizedBox();
            
            // Forzamos el ancho al máximo disponible para eliminar el efecto de reducción
            final sheetWidth = constraints.maxWidth;
            final sheetHeight = sheetWidth * (_pdfPageSize!.height / _pdfPageSize!.width);
            
            final displayScale = sheetWidth / _pdfPageSize!.width;
            
            if (_lastLoggedScale != displayScale) {
              _lastLoggedScale = displayScale;
            }

            return Stack(
              children: [
                 InteractiveViewer(
                  transformationController: _transformationController,
                  maxScale: 10.0,
                  minScale: 1.0, // BLINDAJE: El mínimo es el ancho real de la pantalla
                  boundaryMargin: const EdgeInsets.all(20), // ELIMINAMOS EL LIENZO GIGANTE
                  child: Center(
                    child: Container(
                      width: sheetWidth,
                      height: sheetHeight,
                      decoration: const BoxDecoration(
                        color: Colors.white, 
                        boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 25, spreadRadius: 5)]
                      ),
                      child: Stack(clipBehavior: Clip.none, children: [
                      if (_pageImage != null)
                        SizedBox.expand(child: Image.memory(_pageImage!, fit: BoxFit.fill)),
                      
                      if (_stamps.containsKey(_currentPageIndex))
                        ..._stamps[_currentPageIndex]!.map((s) => _buildStamp(s, displayScale)),
                      
                      if (_selectedSignature != null)
                        Positioned(
                          left: _currentSigPosInPoints.dx * displayScale,
                          top: _currentSigPosInPoints.dy * displayScale,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              final zoomScale = _transformationController.value.getMaxScaleOnAxis();
                              setState(() {
                                _currentSigPosInPoints += details.delta / (displayScale * zoomScale);
                              });
                            },
                            child: Container(
                              width: _currentSigWidthInPoints * displayScale,
                              height: _currentSigHeightInPoints * displayScale,
                              decoration: BoxDecoration(border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5), width: 1)),
                              child: ColorFiltered(colorFilter: ColorFilter.mode(_inkColor, BlendMode.srcIn), child: Image.file(_selectedSignature!, fit: BoxFit.fill)),
                            ),
                          ),
                        ),
                    ]),
                  )),
                ),

              ],
            );
          })),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(children: [
                  Row(children: [
                    // Controles de tamaño compactos
                    Container(
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.remove, color: Colors.white, size: 18), onPressed: () => setState(() { _currentSigWidthInPoints *= 0.9; _currentSigHeightInPoints *= 0.9; })),
                          const Text('TAMAÑO', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                          IconButton(icon: const Icon(Icons.add, color: Colors.white, size: 18), onPressed: () => setState(() { _currentSigWidthInPoints *= 1.1; _currentSigHeightInPoints *= 1.1; })),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botón Deshacer con marco
                    OutlinedButton(
                      onPressed: (_stamps[_currentPageIndex]?.isNotEmpty ?? false) ? _undoLastStamp : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amberAccent,
                        side: const BorderSide(color: Colors.amberAccent, width: 1.5),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Icon(Icons.undo, size: 20),
                    ),
                    const SizedBox(width: 8),
                    // Botón Firmar (reemplaza Incrustar)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _addStamp, 
                        icon: const Icon(Icons.history_edu, size: 18), 
                        label: const Text('FIRMAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), 
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurpleAccent, 
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        )
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botón Guardar Final
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveFinalPdf, 
                        icon: const Icon(Icons.save, size: 16), 
                        label: const Text('GUARDAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), 
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700, 
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        )
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(height: 80, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _availableSignatures.length, itemBuilder: (context, index) {
                    final sig = _availableSignatures[index];
                    final isSelected = _selectedSignature?.path == sig.path;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedSignature = sig), 
                      child: Container(
                        width: 100, 
                        margin: const EdgeInsets.only(right: 12), 
                        decoration: BoxDecoration(
                          color: Colors.white, // FONDO BLANCO SOLIDO
                          borderRadius: BorderRadius.circular(12), 
                          border: Border.all(color: isSelected ? Colors.deepPurpleAccent : Colors.transparent, width: 2)
                        ), 
                        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(sig, fit: BoxFit.fill))
                      )
                    );
                  })),
                ],
              ),
            ),
          ),
      ]),
    );
  }
  
  Widget _qualityBtn(String label, double dpi) {
    bool isSelected = _selectedDpi == dpi;
    return GestureDetector(
      onTap: () => setState(() => _selectedDpi = dpi),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.blueAccent : Colors.white24),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildStamp(SignatureStamp stamp, double displayScale) {
    return Positioned(left: stamp.positionInPoints.dx * displayScale, top: stamp.positionInPoints.dy * displayScale, child: SizedBox(width: stamp.widthInPoints * displayScale, height: stamp.heightInPoints * displayScale, child: ColorFiltered(colorFilter: ColorFilter.mode(stamp.color, BlendMode.srcIn), child: Image.file(stamp.signatureFile, fit: BoxFit.fill))));
  }

  Widget _colorBtn(Color color) {
    return GestureDetector(
      onTap: () => setState(() => _inkColor = color), 
      child: Container(
        width: 24, // Reducido de 28
        height: 24, 
        margin: const EdgeInsets.only(right: 8), // Reducido de 12
        decoration: BoxDecoration(
          color: color, 
          shape: BoxShape.circle, 
          border: Border.all(color: _inkColor == color ? Colors.white : Colors.white24, width: 2), 
          boxShadow: _inkColor == color ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)] : null
        )
      )
    );
  }

  @override
  void dispose() { _transformationController.dispose(); super.dispose(); }
}
