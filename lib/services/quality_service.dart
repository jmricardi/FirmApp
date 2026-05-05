import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

class QualityService {
  
  // Analiza si la imagen tiene suficiente luz
  static Future<Map<String, dynamic>> checkImageQuality(String path) async {
    return await compute(_analyzePixels, path);
  }

  static Future<Map<String, dynamic>> _analyzePixels(String path) async {
    final bytes = File(path).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) return {'isGood': false, 'reason': 'Error al leer imagen'};

    double totalLuminance = 0;
    double maxLum = 0;
    double minLum = 255;
    int count = 0;
    
    // Para detección de nitidez básica (varianza local)
    double totalVariance = 0;

    for (int y = 1; y < image.height - 1; y += 10) {
      for (int x = 1; x < image.width - 1; x += 10) {
        final pixel = image.getPixel(x, y);
        final lum = (0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b);
        
        totalLuminance += lum;
        if (lum > maxLum) maxLum = lum;
        if (lum < minLum) minLum = lum;

        // Varianza local (laplaciano simplificado)
        final pN = image.getPixel(x, y - 1);
        final pS = image.getPixel(x, y + 1);
        final pE = image.getPixel(x + 1, y);
        final pW = image.getPixel(x - 1, y);
        
        final lumN = (0.2126 * pN.r + 0.7152 * pN.g + 0.0722 * pN.b);
        final diff = (lum - lumN).abs();
        totalVariance += diff;

        count++;
      }
    }

    double avgLuminance = totalLuminance / count;
    double contrast = maxLum - minLum;
    double avgVariance = totalVariance / count;
    
    // Criterios mejorados
    if (avgLuminance < 40) return {'isGood': false, 'reason': 'Demasiado oscura'};
    if (avgLuminance > 240) return {'isGood': false, 'reason': 'Demasiada luz (quemada)'};
    if (contrast < 50) return {'isGood': false, 'reason': 'Muy poco contraste'};
    if (avgVariance < 3) return {'isGood': false, 'reason': 'Imagen desenfocada o borrosa'};

    return {'isGood': true, 'reason': 'Calidad aceptable'};
  }
}
