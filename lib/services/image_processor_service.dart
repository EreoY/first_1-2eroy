import 'dart:io';
import 'package:flutter/foundation.dart'; // For compute
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageProcessorService {
  Future<String> processForOCR(File originalFile) async {
    print("[ImageProcessor] Starting processing for: ${originalFile.path}");

    // Get temp dir on main thread (Platform Channel safe)
    final tempDir = await getTemporaryDirectory();
    final tempPath = tempDir.path;

    // Offload heavy lifting to background isolate
    try {
      return await compute(_processImageInIsolate, {
        'inputPath': originalFile.path,
        'tempPath': tempPath,
      });
    } catch (e) {
      print("[ImageProcessor] Compute error: $e. Returning original path.");
      return originalFile.path;
    }
  }
}

// Top-level function for compute
Future<String> _processImageInIsolate(Map<String, String> args) async {
  final inputPath = args['inputPath']!;
  final tempPath = args['tempPath']!;
  final inputFile = File(inputPath);

  try {
    // 1. Decode
    final bytes = await inputFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      print("[ImageProcessor] Failed to decode image. Returning original path.");
      return inputPath;
    }

    // 2. Grayscale (Remove color noise)
    image = img.grayscale(image);

    // 3. Resize (Upscale/Downscale to standard width)
    // 720 is sufficient for OCR (Standard Receipt Width) and faster than 1024
    if (image.width != 1024) {
      image = img.copyResize(image, width: 1024);
    }

    // 4. Enhance Contrast (Make text pop)
    image = img.contrast(image, contrast: 150);

    // 5. Save to Temp
    final fileName = 'processed_slip_${DateTime.now().millisecondsSinceEpoch}.png';
    final processedPath = '$tempPath/$fileName';
    
    final processedFile = File(processedPath);
    await processedFile.writeAsBytes(img.encodePng(image));

    return processedPath;
  } catch (e) {
    print("[ImageProcessor] Error in isolate: $e");
    return inputPath; // Fallback
  }
}
