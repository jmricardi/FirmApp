import 'dart:io';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:pdfrx/pdfrx.dart' as render;
import 'dart:ui' as ui;

class ScannerService {
  // Ahora permitimos hasta 20 hojas por sesión
  final _documentScanner = DocumentScanner(
    options: DocumentScannerOptions(
      documentFormats: {DocumentFormat.jpeg},
      mode: ScannerMode.full,
      isGalleryImport: true, // Corregido: Nombre correcto para v0.4.1
      pageLimit: 20,
    ),
  );


  // Devuelve una lista de rutas de imágenes capturadas
  Future<List<String>?> captureDocuments(
      {bool checkQuality = false, bool isSignature = false}) async {
    try {
      final result = await _documentScanner.scanDocument();
      final images = result.images;
      if (images == null || images.isEmpty) return null;

      List<String> persistentPaths = [];
      for (var tempPath in images) {
        if (checkQuality) {
          final isGood =
              await checkImageQuality(tempPath, isSignature: isSignature);
          if (!isGood) {
            throw Exception("QUALITY_INSUFFICIENT");
          }
        }

        // Guardamos en carpeta temporal primero
        final path =
            await _moveToPersistentStorage(tempPath, isTemporary: true);
        persistentPaths.add(path);
      }
      return persistentPaths;
    } catch (e) {
      if (e.toString().contains("QUALITY_INSUFFICIENT")) rethrow;
      debugPrint('Error en captura: $e');
      return null;
    }
  }

  // Método para validar si la imagen es legible o tiene contenido (firma)
  Future<bool> checkImageQuality(String imagePath,
      {bool isSignature = false}) async {
    try {
      if (!isSignature) {
        // OCR removed to save space. Documents are accepted as-is.
        return true;
      } else {
        // MODO FIRMA: Analizamos densidad de píxeles (contraste) en lugar de caracteres
        final bytes = await File(imagePath).readAsBytes();
        final originalImage = img.decodeImage(bytes);
        if (originalImage == null) return false;

        int inkPixels = 0;
        int sampleStep = 10; // Muestreamos 1 de cada 10 píxeles para velocidad
        int totalSampled = 0;

        for (int y = 0; y < originalImage.height; y += sampleStep) {
          for (int x = 0; x < originalImage.width; x += sampleStep) {
            final pixel = originalImage.getPixel(x, y);
            // Si la luminancia es baja (oscuro = tinta), lo contamos
            if (img.getLuminance(pixel) < 180) {
              inkPixels++;
            }
            totalSampled++;
          }
        }

        // Si hay al menos un 0.5% de densidad de "tinta" en el muestreo, la firma es válida
        final density = inkPixels / totalSampled;
        debugPrint(
            'Densidad de firma detectada: ${density.toStringAsFixed(4)}');
        return density > 0.005;
      }
    } catch (e) {
      debugPrint('Error en checkImageQuality: $e');
      return false;
    }
  }

  Future<String> _moveToPersistentStorage(String tempPath,
      {bool isTemporary = false}) async {
    final directory = await getApplicationDocumentsDirectory();
    final subDir = isTemporary ? 'temp_scans' : 'scans';
    final targetDir = Directory('${directory.path}/$subDir');
    if (!await targetDir.exists()) await targetDir.create(recursive: true);

    final fileName =
        'TEMP_${DateTime.now().millisecondsSinceEpoch}_${tempPath.split('/').last}';
    final newPath = '${targetDir.path}/$fileName';

    await File(tempPath).copy(newPath);
    return newPath;
  }

  Future<void> saveAsJpg(List<String> tempPaths) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) await scansDir.create(recursive: true);

    for (var path in tempPaths) {
      final file = File(path);
      if (await file.exists()) {
        final fileName =
            'A4_IMG_${DateTime.now().millisecondsSinceEpoch}_${path.split('/').last}';
        await file.copy('${scansDir.path}/$fileName');
        // También exportamos a la galería pública
        await Gal.putImage(path);
      }
    }
  }

  Future<void> clearTempScans() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final tempDir = Directory('${directory.path}/temp_scans');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing temp: $e');
    }
  }

  Future<List<File>> getScannedDocuments() async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) return [];

    try {
      return scansDir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<String> renameFile(String path, String newName) async {
    final oldFileName = path.split(Platform.pathSeparator).last;
    String prefix = "";
    if (oldFileName.startsWith('A4_')) {
      prefix = "A4_";
    } else if (oldFileName.startsWith('LTR_'))
      prefix = "LTR_";
    else if (oldFileName.startsWith('LGL_'))
      prefix = "LGL_";
    else if (oldFileName.startsWith('FRM_')) prefix = "FRM_";

    final file = File(path);
    final extension = path.split('.').last;
    final parentDir = file.parent.path;

    // Si el usuario no incluyó el prefijo manualmente, se lo reponemos para no perder la etiqueta
    String finalName = newName;
    if (prefix.isNotEmpty && !newName.startsWith(prefix)) {
      finalName = "$prefix$newName";
    }

    final newPath = '$parentDir/$finalName.$extension';
    return (await file.rename(newPath)).path;
  }

  Future<PdfPageFormat> _detectPdfFormat(String pdfPath) async {
    try {
      final doc = await render.PdfDocument.openFile(pdfPath);
      if (doc.pages.isEmpty) return PdfPageFormat.a4;
      
      final page = doc.pages[0];
      final double width = page.width;
      final double height = page.height;
      
      bool isMatch(double w, double h, double targetW, double targetH) {
        return (w - targetW).abs() <= 10 && (h - targetH).abs() <= 10;
      }

      if (isMatch(width, height, 595.27, 841.89) || isMatch(width, height, 841.89, 595.27)) {
        return PdfPageFormat.a4;
      } else if (isMatch(width, height, 612.0, 792.0) || isMatch(width, height, 792.0, 612.0)) {
        return PdfPageFormat.letter;
      } else if (isMatch(width, height, 612.0, 1008.0) || isMatch(width, height, 1008.0, 612.0)) {
        return PdfPageFormat.legal;
      }
      
      return PdfPageFormat.a4;
    } catch (e) {
      return PdfPageFormat.a4;
    }
  }

  String _getPrefixForFormat(PdfPageFormat format) {
    if (format == PdfPageFormat.letter) return 'LTR_';
    if (format == PdfPageFormat.legal) return 'LGL_';
    return 'A4_';
  }

  // PASO 1: Corrección de Fidelidad y Recorte Simétrico
  Future<String> saveAsPdf(List<String> imagePaths,
      {PdfPageFormat? format}) async {
    final pdf = pw.Document();
    final actualFormat = format ?? PdfPageFormat.a4;
    final prefix = _getPrefixForFormat(actualFormat);
    final String processId = '$prefix${DateTime.now().millisecondsSinceEpoch}';

    for (var path in imagePaths) {
      final imageBytes = File(path).readAsBytesSync();
      final img.Image? originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) continue;

      // 1. DEFINICIÓN DE OBJETIVOS DE PROPORCIÓN (Target AR)
      final double targetW = format?.width ?? 595.27;
      final double targetH = format?.height ?? 841.89;
      final double targetAR = targetW / targetH;
      final double imgAR = originalImage.width / originalImage.height;

      // 2. LÓGICA DE RECORTE ADAPTATIVO (Smart Crop)
      img.Image processedImage;
      int pixelsRemovedX = 0;
      int pixelsRemovedY = 0;

      if ((imgAR - targetAR).abs() > 0.001) {
        if (imgAR > targetAR) {
          // Imagen muy ancha: Center Crop lateral
          final int newWidth = (originalImage.height * targetAR).toInt();
          pixelsRemovedX = (originalImage.width - newWidth);
          final int xOffset = pixelsRemovedX ~/ 2;
          processedImage = img.copyCrop(originalImage,
              x: xOffset, y: 0, width: newWidth, height: originalImage.height);
        } else {
          // Imagen muy alta: Center Crop vertical
          final int newHeight = (originalImage.width / targetAR).toInt();
          pixelsRemovedY = (originalImage.height - newHeight);
          final int yOffset = pixelsRemovedY ~/ 2;
          processedImage = img.copyCrop(originalImage,
              x: 0, y: yOffset, width: originalImage.width, height: newHeight);
        }
      } else {
        processedImage = originalImage;
      }

      // Optimizamos la calidad a 75% para reducir el peso del PDF (Paso 7)
      final encodedImage =
          Uint8List.fromList(img.encodeJpg(processedImage, quality: 75));

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(targetW, targetH, marginAll: 0),
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(
                pw.MemoryImage(encodedImage),
                fit: pw.BoxFit.fill,
              ),
            );
          },
        ),
      );
    }

    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) await scansDir.create(recursive: true);

    final finalPrefix = _getPrefixForFormat(actualFormat);

    final fileName = '$finalPrefix${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File("${scansDir.path}/$fileName");
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  Future<void> exportToPublicGallery(String imagePath) async {
    await Gal.putImage(imagePath);
  }

  Future<void> shareFile(String path) async {
    await Share.shareXFiles([XFile(path)], text: 'Enviado desde FirmApp');
  }

  Future<String> saveCanvasSignature(Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) await scansDir.create(recursive: true);

    final fileName = 'FRM_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File("${scansDir.path}/$fileName");
    await file.writeAsBytes(bytes);

    return file.path;
  }

  Future<String?> importAndNormalizePdf(String pdfPath,
      {PdfPageFormat? format}) async {
    try {
      final actualFormat = format ?? await _detectPdfFormat(pdfPath);
      final doc = await render.PdfDocument.openFile(pdfPath);
      final tempDir = await getTemporaryDirectory();
      List<String> pageImages = [];

      for (int i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        // Renderizamos a alta resolución (300 DPI aprox -> scale 4)
        final pageImg = await page.render(
          fullWidth: page.width * 4,
          fullHeight: page.height * 4,
        );

        if (pageImg != null) {
          final uiImg = await pageImg.createImage();
          final byteData =
              await uiImg.toByteData(format: ui.ImageByteFormat.png);
          final pngBytes = byteData!.buffer.asUint8List();

          final tempPath =
              '${tempDir.path}/norm_${i}_${DateTime.now().millisecondsSinceEpoch}.png';
          await File(tempPath).writeAsBytes(pngBytes);
          pageImages.add(tempPath);

          pageImg.dispose();
          uiImg.dispose();
        }
      }

      // Ahora lo guardamos como un PDF nuevo con el formato deseado
      final resultPath = await saveAsPdf(pageImages, format: actualFormat);

      // Limpiar temporales
      for (var p in pageImages) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }

      return resultPath;
    } catch (e) {
      debugPrint("Error normalizing PDF: $e");
      return null;
    }
  }

  Future<File?> importExternalFile(String externalPath) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final scansDir = Directory('${directory.path}/scans');
      if (!await scansDir.exists()) await scansDir.create(recursive: true);

      final originalFileName = externalPath.split(Platform.pathSeparator).last;
      
      final detectedFormat = await _detectPdfFormat(externalPath);
      final prefix = _getPrefixForFormat(detectedFormat);
      
      final newPath =
          '${scansDir.path}/${prefix}Import_${DateTime.now().millisecondsSinceEpoch}_$originalFileName';
      return await File(externalPath).copy(newPath);
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _documentScanner.close();
  }
}
