import 'dart:io';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

class ScannerService {
  final _documentScanner = DocumentScanner(
    options: DocumentScannerOptions(
      documentFormats: {DocumentFormat.jpeg},
      mode: ScannerMode.full,
      isGalleryImport: true,
      pageLimit: 1,
    ),
  );
  
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<String?> captureDocument() async {
    try {
      final result = await _documentScanner.scanDocument();
      final images = result.images;
      if (images == null || images.isEmpty) return null;
      
      final tempPath = images.first;
      return await _moveToPersistentStorage(tempPath);
    } catch (e) {
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
    
    final fileName = 'EasyScan_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final newPath = '${scansDir.path}/$fileName';
    
    await File(tempPath).rename(newPath);
    return newPath;
  }

  Future<List<File>> getScannedDocuments() async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) return [];
    
    return scansDir.listSync()
        .whereType<File>()
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> renameFile(String path, String newName) async {
    final file = File(path);
    final extension = path.split('.').last;
    final parentDir = file.parent.path;
    final newPath = '$parentDir/$newName.$extension';
    
    final renamedFile = await file.rename(newPath);
    return renamedFile.path;
  }

  Future<String> saveAsPdf(String imagePath) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(File(imagePath).readAsBytesSync());
    
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Center(
          child: pw.Image(image),
        ),
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    final fileName = 'EasyScan_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File("${scansDir.path}/$fileName");
    
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  Future<String> saveAsText(String text) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    final fileName = 'EasyText_${DateTime.now().millisecondsSinceEpoch}.txt';
    final file = File("${scansDir.path}/$fileName");
    
    await file.writeAsString(text);
    return file.path;
  }

  Future<void> exportToPublicGallery(String imagePath) async {
    await Gal.putImage(imagePath);
  }

  Future<void> shareFile(String path) async {
    await Share.shareXFiles([XFile(path)], text: 'Documento compartido desde EasyScan');
  }

  void dispose() {
    _documentScanner.close();
    _textRecognizer.close();
  }
}
