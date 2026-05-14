import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as render;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../services/credit_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/custom_app_bar.dart';

class TextStamp {
  String text;
  Offset positionInPoints;
  double fontSize;
  Color color;

  TextStamp({
    required this.text,
    required this.positionInPoints,
    required this.fontSize,
    required this.color,
  });
}

class PdfFillScreen extends StatefulWidget {
  final File pdfFile;

  const PdfFillScreen({super.key, required this.pdfFile});

  @override
  State<PdfFillScreen> createState() => _PdfFillScreenState();
}

class _PdfFillScreenState extends State<PdfFillScreen> {
  render.PdfDocument? _doc;
  int _totalPages = 0;
  int _currentPageIndex = 0;
  Uint8List? _pageImage;

  String _currentText = "Texto de ejemplo";
  double _currentFontSize = 14.0;
  Color _inkColor = Colors.black;
  double _selectedDpi = 250.0;
  bool _isLoading = true;
  bool _isSaving = false;
  String _saveProgress = "";
  Size? _pdfPageSize;
  final GlobalKey _pageContainerKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();
  final TransformationController _transformationController = TransformationController();

  Offset _currentTextPosInPoints = const Offset(50, 50);
  Offset? _dragStartGlobal;
  bool _isDragging = false;
  Offset _dragGlobalPos = Offset.zero;

  final Map<int, List<TextStamp>> _stamps = {};

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
            _transformationController.value = Matrix4.identity();
            // Centrar el texto inicial
            _currentTextPosInPoints = Offset(page.width / 2 - 50, page.height / 2);
          });
        }
        pageImage.dispose();
        uiImage.dispose();
      }
    } catch (e) {
      debugPrint("DEBUG RENDER ERROR: $e");
    }
  }

  void _addTextStamp() {
    setState(() {
      _stamps.putIfAbsent(_currentPageIndex, () => []).add(
            TextStamp(
              text: _currentText,
              positionInPoints: _currentTextPosInPoints,
              fontSize: _currentFontSize,
              color: _inkColor,
            ),
          );
    });
  }

  void _undoLastText() {
    setState(() {
      final stamps = _stamps[_currentPageIndex];
      if (stamps != null && stamps.isNotEmpty) {
        stamps.removeLast();
        if (stamps.isEmpty) _stamps.remove(_currentPageIndex);
      }
    });
  }

  Future<void> _showTextInputDialog() async {
    final controller = TextEditingController(text: _currentText);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Ingresar Texto", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Escribe aquí...",
            hintStyle: TextStyle(color: Colors.white24),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _currentText = controller.text);
              Navigator.pop(context);
            },
            child: const Text("Aceptar"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveFinalPdf() async {
    if (_doc == null || _pdfPageSize == null) return;

    final creditService = context.read<CreditService>();
    if (creditService.credits < 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Créditos insuficientes (1 crédito)'),
            backgroundColor: Colors.redAccent));
      }
      return;
    }

    setState(() => _isSaving = true);

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
            Text("Procesando Documento",
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Calidad: ${_selectedDpi.toInt()} DPI",
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );

    try {
      final success = await creditService.useCredit(
          amount: 1, description: "Completar Formulario PDF");
      if (!success) throw Exception("Error al procesar créditos");

      final pdf = pw.Document();

      for (int i = 0; i < _totalPages; i++) {
        final page = _doc!.pages[i];
        final double originalPageW = page.width;
        final double originalPageH = page.height;

        final double nativeScale = _selectedDpi / 72.0;
        final int renderW = (originalPageW * nativeScale).toInt();
        final int renderH = (originalPageH * nativeScale).toInt();

        final pageRender = await page.render(
          width: renderW,
          height: renderH,
          fullWidth: renderW.toDouble(),
          fullHeight: renderH.toDouble(),
        );
        final pageUiImg = await pageRender!.createImage();
        final pageBytes = await pageUiImg.toByteData(format: ui.ImageByteFormat.png);
        final bgImage = pw.MemoryImage(pageBytes!.buffer.asUint8List());

        final List<pw.Widget> textWidgets = [];
        if (_stamps.containsKey(i)) {
          for (var stamp in _stamps[i]!) {
            textWidgets.add(
              pw.Positioned(
                left: stamp.positionInPoints.dx + 2.0,
                top: stamp.positionInPoints.dy,
                child: pw.Text(
                  stamp.text,
                  style: pw.TextStyle(
                    fontSize: stamp.fontSize,
                    color: PdfColor.fromInt(stamp.color.value),
                    height: 1.0,
                  ),
                ),
              ),
            );
          }
        }

        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat(originalPageW, originalPageH, marginAll: 0),
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Stack(
                children: [
                  pw.Positioned.fill(child: pw.Image(bgImage, fit: pw.BoxFit.fill)),
                  ...textWidgets,
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
      final fileName = 'FF_FILLED_${originalName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outputFile = File('${directory.path}/scans/$fileName');
      if (!outputFile.parent.existsSync()) outputFile.parent.createSync();
      await outputFile.writeAsBytes(await pdf.save());

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("DEBUG SAVE ERROR: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
            child: Column(
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
      appBar: const FirmAppAppBar(showSettings: false),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          color: Colors.black,
          child: Row(children: [
            const Text('COLOR:', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
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
            Text('${_currentPageIndex + 1} / $_totalPages',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            IconButton(
                constraints: const BoxConstraints(maxWidth: 32),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_left, color: Colors.white, size: 20),
                onPressed: _currentPageIndex > 0 ? () => _loadPage(_currentPageIndex - 1) : null),
            IconButton(
                constraints: const BoxConstraints(maxWidth: 32),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_right, color: Colors.white, size: 20),
                onPressed: _currentPageIndex < _totalPages - 1 ? () => _loadPage(_currentPageIndex + 1) : null),
          ]),
        ),

        // DPI Selector
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
          final double scaleX = sheetWidth / _pdfPageSize!.width;
          final double scaleY = sheetHeight / _pdfPageSize!.height;

          return Stack(
            key: _stackKey,
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
                    decoration: const BoxDecoration(color: Colors.white, boxShadow: [
                      BoxShadow(color: Colors.black87, blurRadius: 25, spreadRadius: 5)
                    ]),
                    child: RepaintBoundary(
                      child: Stack(clipBehavior: Clip.none, children: [
                        if (_pageImage != null)
                          SizedBox.expand(child: Image.memory(_pageImage!, fit: BoxFit.fill)),
  
                        // Pre-placed stamps
                        if (_stamps.containsKey(_currentPageIndex))
                          ..._stamps[_currentPageIndex]!.map((s) => _buildStamp(s, scaleX, scaleY)),
  
                        // Current active text being positioned
                        Positioned(
                          left: _currentTextPosInPoints.dx * scaleX,
                          top: _currentTextPosInPoints.dy * scaleY,
                          child: GestureDetector(
                            onPanStart: (details) {
                              final RenderBox? box = _pageContainerKey.currentContext?.findRenderObject() as RenderBox?;
                              if (box == null) return;
                              final Offset localTouch = box.globalToLocal(details.globalPosition);
                              final Offset textCorner = Offset(_currentTextPosInPoints.dx * scaleX, _currentTextPosInPoints.dy * scaleY);
                              _dragStartGlobal = localTouch - textCorner;
                              setState(() {
                                 _isDragging = true;
                                 _dragGlobalPos = details.globalPosition;
                              });
                            },
                            onPanUpdate: (details) {
                              if (_dragStartGlobal == null) return;
                              final RenderBox? box = _pageContainerKey.currentContext?.findRenderObject() as RenderBox?;
                              if (box == null) return;
                              final Offset localTouch = box.globalToLocal(details.globalPosition);
                              final Offset textCorner = localTouch - _dragStartGlobal!;
  
                              final double pdfX = (textCorner.dx / scaleX).clamp(0, _pdfPageSize!.width);
                              final double pdfY = (textCorner.dy / scaleY).clamp(0, _pdfPageSize!.height);
  
                              setState(() {
                                _currentTextPosInPoints = Offset(pdfX, pdfY);
                                _dragGlobalPos = details.globalPosition;
                              });
                            },
                            onPanEnd: (_) => setState(() {
                              _dragStartGlobal = null;
                              _isDragging = false;
                            }),
                            child: Container(
                              decoration: BoxDecoration(
                                  border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 1)),
                              child: Text(
                                _currentText,
                                style: TextStyle(
                                  fontSize: _currentFontSize * scaleY,
                                  color: _inkColor,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
              
              // Lupa (Magnifier)
              if (_isDragging)
                Builder(builder: (context) {
                  final RenderBox? stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
                  if (stackBox == null) return const SizedBox();
                  final Offset stackLocal = stackBox.globalToLocal(_dragGlobalPos);
                  return Positioned(
                    left: stackLocal.dx - 55,
                    top: stackLocal.dy - 140,
                    child: IgnorePointer(
                      child: RawMagnifier(
                        decoration: MagnifierDecoration(
                          shape: CircleBorder(side: BorderSide(color: Colors.blueAccent, width: 2)),
                        ),
                        focalPointOffset: Offset(0, 85),
                        size: const Size(110, 110),
                        magnificationScale: 2.0,
                      ),
                    ),
                  );
                }),
              
              // Telemetry
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
                        Text("PDF X: ${_currentTextPosInPoints.dx.toStringAsFixed(1)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 8)),
                        Text("PDF Y: ${_currentTextPosInPoints.dy.toStringAsFixed(1)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 8)),
                        Text("PAGE: ${_pdfPageSize?.width.toInt()}x${_pdfPageSize?.height.toInt()}", style: const TextStyle(color: Colors.white, fontSize: 7)),
                      ],
                    ),
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
            decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(
              children: [
                Row(children: [
                  // Font Size controls
                  Container(
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.remove, color: Colors.white, size: 18),
                            onPressed: () => setState(() => _currentFontSize = (_currentFontSize - 1).clamp(6, 100))),
                        const Text('A', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                        IconButton(
                            icon: const Icon(Icons.add, color: Colors.white, size: 18),
                            onPressed: () => setState(() => _currentFontSize = (_currentFontSize + 1).clamp(6, 100))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Undo button
                  OutlinedButton(
                    onPressed: (_stamps[_currentPageIndex]?.isNotEmpty ?? false) ? _undoLastText : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amberAccent,
                      side: const BorderSide(color: Colors.amberAccent, width: 1.5),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Icon(Icons.undo, size: 20),
                  ),
                  const SizedBox(width: 8),
                  // Add Text Button (Tt)
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed: _addTextStamp,
                        icon: const Icon(Icons.text_fields, size: 18),
                        label: const Text('Tt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
                  ),
                  const SizedBox(width: 8),
                  // Save button
                  Expanded(
                    child: ElevatedButton.icon(
                        onPressed: _saveFinalPdf,
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('GUARDAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
                  ),
                ]),
                const SizedBox(height: 12),
                // Edit Text Bar
                InkWell(
                  onTap: _showTextInputDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit, color: Colors.white70, size: 16),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_currentText, style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const Icon(Icons.chevron_right, color: Colors.white24),
                      ],
                    ),
                  ),
                ),
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

  Widget _buildStamp(TextStamp stamp, double scaleX, double scaleY) {
    return Positioned(
      left: stamp.positionInPoints.dx * scaleX,
      top: stamp.positionInPoints.dy * scaleY,
      child: Text(
        stamp.text,
        style: TextStyle(
          fontSize: stamp.fontSize * scaleY,
          color: stamp.color,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _colorBtn(Color color) {
    return GestureDetector(
        onTap: () => setState(() => _inkColor = color),
        child: Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: _inkColor == color ? Colors.white : Colors.white24, width: 2))));
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }
}
