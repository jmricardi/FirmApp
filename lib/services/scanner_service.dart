import 'dart:io';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';

class ScannerService {
  // Ahora permitimos hasta 20 hojas por sesión
  final _documentScanner = DocumentScanner(
    options: DocumentScannerOptions(
      documentFormats: {DocumentFormat.jpeg},
      mode: ScannerMode.full,
      isGalleryImport: true,
      pageLimit: 20, 
    ),
  );
  
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  
  // Devuelve una lista de rutas de imágenes capturadas
  Future<List<String>?> captureDocuments() async {
    try {
      final result = await _documentScanner.scanDocument();
      final images = result.images;
      if (images == null || images.isEmpty) return null;
      
      List<String> persistentPaths = [];
      for (var tempPath in images) {
        final path = await _moveToPersistentStorage(tempPath);
        persistentPaths.add(path);
      }
      return persistentPaths;
    } catch (e) {
      debugPrint('Error en captura: $e');
      return null;
    }
  }

  Future<String> recognizeText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      return "Error al reconocer texto: $e";
    }
  }

  Future<String> _moveToPersistentStorage(String tempPath) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) await scansDir.create(recursive: true);
    
    final fileName = 'FirmaFacil_${DateTime.now().millisecondsSinceEpoch}_${tempPath.split('/').last}';
    final newPath = '${scansDir.path}/$fileName';
    
    await File(tempPath).copy(newPath);
    return newPath;
  }

  Future<List<File>> getScannedDocuments() async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) return [];
    
    try {
      return scansDir.listSync()
          .whereType<File>()
          .toList()
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
    final file = File(path);
    final extension = path.split('.').last;
    final parentDir = file.parent.path;
    final newPath = '$parentDir/$newName.$extension';
    return (await file.rename(newPath)).path;
  }

  // AHORA: Soporta múltiples imágenes para crear un solo PDF
  Future<String> saveAsPdf(List<String> imagePaths) async {
    final pdf = pw.Document();
    
    for (var path in imagePaths) {
      final image = pw.MemoryImage(File(path).readAsBytesSync());
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) => pw.Center(child: pw.Image(image)),
        ),
      );
    }

    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) await scansDir.create(recursive: true);
    
    final fileName = 'FirmaFacil_Doc_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File("${scansDir.path}/$fileName");
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  Future<String> saveAsText(String text) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) await scansDir.create(recursive: true);

    final fileName = 'FirmaText_${DateTime.now().millisecondsSinceEpoch}.txt';
    final file = File("${scansDir.path}/$fileName");
    await file.writeAsString(text);
    return file.path;
  }

  Future<void> exportToPublicGallery(String imagePath) async {
    await Gal.putImage(imagePath);
  }

  Future<void> shareFile(String path) async {
    await Share.shareXFiles([XFile(path)], text: 'Enviado desde FirmaFacil');
  }

  Future<File?> importExternalFile(String externalPath) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final scansDir = Directory('${directory.path}/scans');
      if (!await scansDir.exists()) await scansDir.create(recursive: true);
      
      final originalFileName = externalPath.split(Platform.pathSeparator).last;
      final newPath = '${scansDir.path}/Import_${DateTime.now().millisecondsSinceEpoch}_$originalFileName';
      return await File(externalPath).copy(newPath);
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _documentScanner.close();
    _textRecognizer.close();
  }
}
