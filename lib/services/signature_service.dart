import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class SignatureService {
  // Proceso 1A: Transparencia Base (Holograma Real)
  Future<String?> processSignaturePhoto(String path,
      {bool isFromCamera = true}) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) await scansDir.create(recursive: true);
    final outPath =
        '${scansDir.path}/TEMP_FRM_Base_${DateTime.now().millisecondsSinceEpoch}.png';

    return await compute(_extractBaseSignature, {
      'input': path,
      'output': outPath,
      'isFromCamera': isFromCamera,
    });
  }

  // Proceso 1B: Refuerzo de Tinta y Nitidez (Opcional)
  Future<String?> improveSignatureLocally(String path) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) await scansDir.create(recursive: true);
    final outPath =
        '${scansDir.path}/TEMP_FRM_Mejorada_${DateTime.now().millisecondsSinceEpoch}.png';

    return await compute(_applyLocalImprovement, {
      'input': path,
      'output': outPath,
    });
  }

  static Future<String?> _extractBaseSignature(
      Map<String, dynamic> params) async {
    final inputPath = params['input']!;
    final outputPath = params['output']!;
    final isFromCamera = params['isFromCamera'] ?? true;

    final bytes = File(inputPath).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    // TRATAMIENTO DIFERENCIADO:
    // Solo aplicamos suavizado si viene de la cámara para limpiar el ruido del sensor.
    // Si es importado, mantenemos la nitidez original del archivo.
    if (isFromCamera) {
      img.gaussianBlur(image, radius: 1);
    }

    final rgbaImage = image.convert(numChannels: 4);

    for (var pixel in rgbaImage) {
      final r = pixel.r;
      final g = pixel.g;
      final b = pixel.b;

      final luminance = (0.299 * r + 0.587 * g + 0.114 * b);

      // Algoritmo de Limpieza Quirúrgica:
      // Si es muy claro (> 180), lo hacemos totalmente transparente (el papel)
      if (luminance > 180) {
        pixel.a = 0;
      } else {
        // Si es oscuro (la tinta), lo forzamos a Negro Tinta (#000814) para que sea realista
        // y aplicamos una opacidad proporcional para suavizar los bordes (anti-aliasing)
        pixel.r = 0;
        pixel.g = 8;
        pixel.b = 20;

        if (luminance < 100) {
          pixel.a = 255;
        } else {
          final alpha = ((180 - luminance) / (180 - 100) * 255).toInt();
          pixel.a = alpha.clamp(0, 255);
        }
      }
    }

    File(outputPath).writeAsBytesSync(img.encodePng(rgbaImage));
    return outputPath;
  }

  static Future<String?> _applyLocalImprovement(
      Map<String, String> paths) async {
    final inputPath = paths['input']!;
    final outputPath = paths['output']!;

    final bytes = File(inputPath).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    // Aplicamos refuerzo de contraste para "ennegrecer" la tinta
    final improved = img.adjustColor(
      image,
      contrast: 1.4,
      brightness: 1.05,
    );

    File(outputPath).writeAsBytesSync(img.encodePng(improved));
    return outputPath;
  }

  Future<String> saveCanvasSignature(Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) await scansDir.create(recursive: true);

    final path =
        '${scansDir.path}/TEMP_FRM_Digital_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  Future<void> finalizeSignature(String tempPath) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final scansDir = Directory('${directory.path}/scans');
      if (!scansDir.existsSync()) scansDir.createSync();

      final fileName =
          'FRM_${DateTime.now().millisecondsSinceEpoch}_${tempPath.hashCode.abs()}.png';
      final finalPath = '${scansDir.path}/$fileName';

      final file = File(tempPath);
      await file.copy(finalPath);
    } catch (e) {
      debugPrint("Error finalizando firma: $e");
    }
  }

  Future<List<File>> getSignatures() async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) return [];

    try {
      return scansDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('FRM_'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    } catch (e) {
      return [];
    }
  }

  Future<void> cleanupTemporaries() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final scansDir = Directory('${directory.path}/scans');
      if (await scansDir.exists()) {
        final files = scansDir.listSync();
        for (var file in files) {
          if (file is File && file.path.contains('TEMP_FRM_')) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint("Error cleaning up: $e");
    }
  }
}
