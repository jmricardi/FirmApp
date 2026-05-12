import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class SignatureCaptureService {
  /// Procesa los bytes de la firma capturada desde el canvas.
  /// Realiza un auto-crop robusto y optimizado.
  Future<Uint8List?> processCanvasSignature(Uint8List bytes,
      {int rotationTurns = 0}) async {
    return await compute(_processSignatureTask, {
      'bytes': bytes,
      'rotationTurns': rotationTurns,
    });
  }

  static Uint8List? _processSignatureTask(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final int rotationTurns = params['rotationTurns'];

    final rawImage = img.decodePng(bytes);
    if (rawImage == null) return null;

    // 1. AUTO-CROP ROBUSTO Y OPTIMIZADO
    // Threshold de 20 para evitar ruido y transparencias mínimas
    const int threshold = 20;

    int minX = rawImage.width;
    int maxX = 0;
    int minY = rawImage.height;
    int maxY = 0;
    bool found = false;

    // Optimización: Escaneo de límites (Bounds)
    // Encontrar minY
    for (int y = 0; y < rawImage.height; y++) {
      for (int x = 0; x < rawImage.width; x++) {
        if (rawImage.getPixel(x, y).a > threshold) {
          minY = y;
          found = true;
          break;
        }
      }
      if (found) break;
    }

    if (!found) return null; // Firma vacía o invisible

    // Encontrar maxY
    found = false;
    for (int y = rawImage.height - 1; y >= 0; y--) {
      for (int x = 0; x < rawImage.width; x++) {
        if (rawImage.getPixel(x, y).a > threshold) {
          maxY = y;
          found = true;
          break;
        }
      }
      if (found) break;
    }

    // Encontrar minX
    found = false;
    for (int x = 0; x < rawImage.width; x++) {
      for (int y = minY; y <= maxY; y++) {
        if (rawImage.getPixel(x, y).a > threshold) {
          minX = x;
          found = true;
          break;
        }
      }
      if (found) break;
    }

    // Encontrar maxX
    found = false;
    for (int x = rawImage.width - 1; x >= 0; x--) {
      for (int y = minY; y <= maxY; y++) {
        if (rawImage.getPixel(x, y).a > threshold) {
          maxX = x;
          found = true;
          break;
        }
      }
      if (found) break;
    }

    // 2. APLICAR PADDING Y LÍMITES SEGUROS (Corrección Matemática)
    const int padding = 20;
    minX = (minX - padding).clamp(0, rawImage.width - 1);
    minY = (minY - padding).clamp(0, rawImage.height - 1);
    maxX = (maxX + padding).clamp(0, rawImage.width - 1);
    maxY = (maxY + padding).clamp(0, rawImage.height - 1);

    // Evitamos el error off-by-one sumando 1 al delta
    final int cropW = (maxX - minX) + 1;
    final int cropH = (maxY - minY) + 1;

    // 3. NUEVA VALIDACIÓN DE FIRMA (Área y dimensiones realistas)
    final int area = cropW * cropH;
    if (area < 15000 || cropW < 120 || cropH < 40) {
      return null; // Firma inválida o demasiado pequeña
    }

    // 4. RECORTAR Y APLICAR EFECTO TINTA REALISTA (Optimización de Memoria)
    var processedImage =
        img.copyCrop(rawImage, x: minX, y: minY, width: cropW, height: cropH);

    // 5. APLICAR ROTACIÓN SI ES NECESARIO (Solo en el bitmap final para evitar deformaciones en el canvas)
    if (rotationTurns != 0) {
      processedImage =
          img.copyRotate(processedImage, angle: rotationTurns * 90);
    }

    // --- ALGORITMO DE REFINAMIENTO DE TINTA ---
    // 1. Aplicamos un desenfoque casi imperceptible para romper los bordes vectoriales
    img.gaussianBlur(processedImage, radius: 1);

    // 2. Ajustamos los niveles para que el centro del trazo sea denso y los bordes suaves
    for (var pixel in processedImage) {
      if (pixel.a > 0) {
        // Mantenemos el color Negro Tinta Real (#000814)
        pixel.r = 0;
        pixel.g = 8;
        pixel.b = 20;

        // Simulamos la absorción de la tinta:
        if (pixel.a < 180) {
          pixel.a = (pixel.a * 0.85).toInt();
        }
      }
    }

    // Generamos los bytes finales
    final Uint8List resultBytes =
        Uint8List.fromList(img.encodePng(processedImage));

    return resultBytes;
  }

  /// Guarda la firma procesada en el almacenamiento persistente.
  Future<String> saveSignature(Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${directory.path}/scans');
    if (!await scansDir.exists()) await scansDir.create(recursive: true);

    final fileName = 'FRM_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File("${scansDir.path}/$fileName");
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
