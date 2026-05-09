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


  final _sigService = SignatureService();
  render.PdfDocument? _doc;
  int _totalPages = 0;
  int _currentPageIndex = 0;
  Uint8List? _pageImage;
  
  List<File> _availableSignatures = [];
  File? _selectedSignature;
  
  Offset _currentSigPosInPoints = const Offset(50, 50);
  double _currentSigWidthInPoints = 180;
  double _currentSigHeightInPoints = 100;
  Color _inkColor = Colors.black;
  double _selectedDpi = 250.0;
  bool _isSaving = false;
  
  // Variable para el arrastre preciso de la firma
  Offset? _dragStartGlobal; // Offset entre punto de toque y esquina de la firma
  
  final Map<int, List<SignatureStamp>> _stamps = {};

  bool _isLoading = true;
  String _saveProgress = "";
  Size? _pdfPageSize; 
  final GlobalKey _pageContainerKey = GlobalKey();
  
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
        
        debugPrint("UI_RENDER: requested=${w}x$h | actual=${uiImage.width}x${uiImage.height} | pdfPts=${page.width}x${page.height}");
        debugPrint("UI_RENDER AR: page=${page.height / page.width} | image=${uiImage.height / uiImage.width}");
        
        final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        
        if (mounted) {
          setState(() {
            _pageImage = byteData!.buffer.asUint8List();
            _pdfPageSize = Size(page.width, page.height);
            _currentPageIndex = index;
            _transformationController.value = Matrix4.identity();
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

        // DENSIDAD: Convertimos puntos PDF a píxeles para la rasterización del fondo
        final double nativeScale = _selectedDpi / 72.0;
        final int renderW = (originalPageW * nativeScale).toInt();
        final int renderH = (originalPageH * nativeScale).toInt();

        // Renderizar la página del PDF original como imagen de fondo
        final pageRender = await page.render(
          width: renderW, 
          height: renderH,
          fullWidth: renderW.toDouble(),
          fullHeight: renderH.toDouble(),
        );
        final pageUiImg = await pageRender!.createImage();
        final pageBytes = await pageUiImg.toByteData(format: ui.ImageByteFormat.png);
        final bgImage = pw.MemoryImage(pageBytes!.buffer.asUint8List());

        debugPrint("EXPORT PAGE[$i]: pdfPts=${originalPageW}x$originalPageH | renderPx=${renderW}x$renderH | actualPx=${pageUiImg.width}x${pageUiImg.height}");

        // Preparar las firmas para esta página como imágenes independientes
        final List<pw.Widget> stampWidgets = [];
        
        if (_stamps.containsKey(i)) {
          for (var stamp in _stamps[i]!) {
            final sigBytes = stamp.signatureFile.readAsBytesSync();
            final sigCodec = await ui.instantiateImageCodec(sigBytes);
            final sigFrame = await sigCodec.getNextFrame();
            final sigUiImg = sigFrame.image;
            
            // Aplicar el filtro de color a la firma
            final sigRecorder = ui.PictureRecorder();
            final sigCanvas = Canvas(sigRecorder);
            sigCanvas.drawImageRect(
              sigUiImg,
              Rect.fromLTWH(0, 0, sigUiImg.width.toDouble(), sigUiImg.height.toDouble()),
              Rect.fromLTWH(0, 0, sigUiImg.width.toDouble(), sigUiImg.height.toDouble()),
              Paint()
                ..colorFilter = ui.ColorFilter.mode(stamp.color, ui.BlendMode.srcIn)
                ..filterQuality = ui.FilterQuality.high
            );
            final coloredSigImg = await sigRecorder.endRecording().toImage(sigUiImg.width, sigUiImg.height);
            final coloredSigBytes = await coloredSigImg.toByteData(format: ui.ImageByteFormat.png);
            final sigPwImage = pw.MemoryImage(coloredSigBytes!.buffer.asUint8List());

            debugPrint("STAMP[$i]: pos=(${stamp.positionInPoints.dx}, ${stamp.positionInPoints.dy}) | size=(${stamp.widthInPoints}x${stamp.heightInPoints}) | page=(${originalPageW}x$originalPageH)");

            // POSICIONAMIENTO DIRECTO EN PUNTOS PDF
            // Las coordenadas de la firma están en puntos PDF (mismo sistema que el pageFormat)
            // No se necesita NINGUNA conversión de escala — uso directo 1:1
            stampWidgets.add(
              pw.Positioned(
                left: stamp.positionInPoints.dx,
                top: stamp.positionInPoints.dy,
                child: pw.SizedBox(
                  width: stamp.widthInPoints,
                  height: stamp.heightInPoints,
                  child: pw.Image(sigPwImage, fit: pw.BoxFit.fill),
                ),
              ),
            );

            sigUiImg.dispose();
            coloredSigImg.dispose();
          }
        }

        // Construir la página: fondo rasterizado + firmas posicionadas en coordenadas PDF nativas
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat(originalPageW, originalPageH, marginAll: 0),
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Stack(
                children: [
                  // Capa 1: Imagen de fondo del documento original
                  pw.Positioned.fill(
                    child: pw.Image(bgImage, fit: pw.BoxFit.fill),
                  ),
                  // Capa 2+: Firmas posicionadas con coordenadas PDF directas
                  ...stampWidgets,
                ],
              ),
            );
          },
        ));

        pageRender.dispose();
        pageUiImg.dispose();
      }
      
      final directory = await getApplicationDocumentsDirectory();
      final originalName = widget.pdfFile.path.split(Platform.pathSeparator).last.split('.').first;
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
            
            final sheetWidth = constraints.maxWidth;
            final sheetHeight = sheetWidth * (_pdfPageSize!.height / _pdfPageSize!.width);
            
            // FUENTE UNICA DE VERDAD GEOMETRICA
            final double scaleX = sheetWidth / _pdfPageSize!.width;
            final double scaleY = sheetHeight / _pdfPageSize!.height;

            return Stack(
              children: [
                 InteractiveViewer(
                  transformationController: _transformationController,
                  maxScale: 10.0,
                  minScale: 1.0,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(20),
                  child: Center(
                    child: Container(
                      key: _pageContainerKey,
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
                        ..._stamps[_currentPageIndex]!.map((s) => _buildStamp(s, scaleX, scaleY)),
                      
                      if (_selectedSignature != null)
                        Positioned(
                          left: _currentSigPosInPoints.dx * scaleX,
                          top: _currentSigPosInPoints.dy * scaleY,
                          child: GestureDetector(
                            onPanStart: (details) {
                              final RenderBox? box = _pageContainerKey.currentContext?.findRenderObject() as RenderBox?;
                              if (box == null) return;
                              final Offset localTouch = box.globalToLocal(details.globalPosition);
                              final Offset sigCorner = Offset(
                                _currentSigPosInPoints.dx * scaleX,
                                _currentSigPosInPoints.dy * scaleY,
                              );
                              _dragStartGlobal = localTouch - sigCorner;
                              debugPrint("GEOM: scaleX=$scaleX | scaleY=$scaleY | sheetSize=${sheetWidth}x$sheetHeight | pdfSize=${_pdfPageSize}");
                            },
                            onPanUpdate: (details) {
                              final RenderBox? box = _pageContainerKey.currentContext?.findRenderObject() as RenderBox?;
                              if (box == null || _dragStartGlobal == null) return;
                              final Offset localTouch = box.globalToLocal(details.globalPosition);
                              final Offset sigCorner = localTouch - _dragStartGlobal!;
                              // Misma escala para captura y render
                              final double pdfX = (sigCorner.dx / scaleX).clamp(0, _pdfPageSize!.width - _currentSigWidthInPoints);
                              final double pdfY = (sigCorner.dy / scaleY).clamp(0, _pdfPageSize!.height - _currentSigHeightInPoints);
                              setState(() {
                                _currentSigPosInPoints = Offset(pdfX, pdfY);
                              });
                            },
                            onPanEnd: (_) {
                              _dragStartGlobal = null;
                            },
                            child: Container(
                              width: _currentSigWidthInPoints * scaleX,
                              height: _currentSigHeightInPoints * scaleY,
                              decoration: BoxDecoration(border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.5), width: 1)),
                              child: ColorFiltered(colorFilter: ColorFilter.mode(_inkColor, BlendMode.srcIn), child: Image.file(_selectedSignature!, fit: BoxFit.fill)),
                            ),
                          ),
                        ),

                      // MARCADOR DE ORIGEN (0,0) REAL DEL PDF
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1))),
                      ),

                      // PANEL DE TELEMETRÍA INTERNO
                      Positioned(
                        top: 5,
                        right: 5,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text("PDF X: ${_currentSigPosInPoints.dx.toStringAsFixed(1)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 8)),
                                Text("PDF Y: ${_currentSigPosInPoints.dy.toStringAsFixed(1)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 8)),
                                Text("PAGE: ${_pdfPageSize?.width.toInt()}x${_pdfPageSize?.height.toInt()}", style: const TextStyle(color: Colors.white, fontSize: 7)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ]),
                    ),
                  ),
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

  Widget _buildStamp(SignatureStamp stamp, double scaleX, double scaleY) {
    return Positioned(left: stamp.positionInPoints.dx * scaleX, top: stamp.positionInPoints.dy * scaleY, child: SizedBox(width: stamp.widthInPoints * scaleX, height: stamp.heightInPoints * scaleY, child: ColorFiltered(colorFilter: ColorFilter.mode(stamp.color, BlendMode.srcIn), child: Image.file(stamp.signatureFile, fit: BoxFit.fill))));
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
