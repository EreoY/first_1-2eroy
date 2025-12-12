import 'dart:io';
import 'dart:math'; // For min/max
import 'dart:ui' as ui; // For Image info
import 'package:flutter/foundation.dart'; // For compute
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path_provider/path_provider.dart';
import '../services/theme_service.dart';

class BillScannerScreen extends StatefulWidget {
  final File imageFile;

  const BillScannerScreen({super.key, required this.imageFile});

  @override
  State<BillScannerScreen> createState() => _BillScannerScreenState();
}

class _BillScannerScreenState extends State<BillScannerScreen> {
  late File _currentImage;
  bool _isProcessing = false;
  bool _isFiltered = false;
  
  // Scan State
  String? _extractedText; // For final return
  List<TesseractBlock> _textBlocks = []; // For overlay
  ui.Image? _uiImage; // For scaling coordinates
  bool _isScanned = false;
  
  // Drawing State
  bool _isDrawingMode = false;
  List<Offset> _drawingPoints = [];
  Rect? _roiRect; // Region of Interest in Image Coordinates
  int? _activeHandle; // 0: TL, 1: TR, 2: BL, 3: BR, null: None
  double _lastScale = 1.0; // To convert screen coords to image coords

  @override
  void initState() {
    super.initState();
    _currentImage = widget.imageFile;
    _loadUiImage(_currentImage); // Load initial image into ui.Image
    // Auto-process on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processImage(auto: true);
    });
  }

  Future<void> _processImage({bool auto = false}) async {
    if (_isFiltered && auto) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final bytes = await _currentImage.readAsBytes();
      final processedBytes = await compute(_processImageInIsolate, bytes);

      if (processedBytes != null) {
        final directory = await getTemporaryDirectory();
        final filteredPath = '${directory.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final filteredFile = File(filteredPath)..writeAsBytesSync(processedBytes);

        if (mounted) {
          setState(() {
            _currentImage = filteredFile;
            _isFiltered = true;
            _isScanned = false; // Reset scan state
            _extractedText = null;
            _textBlocks = [];
            _uiImage = null;
          });
          _loadUiImage(_currentImage);
        }
      }
    } catch (e) {
      print("Error processing image: $e");
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  static Uint8List? _processImageInIsolate(Uint8List bytes) {
    img.Image? original = img.decodeImage(bytes);
    if (original == null) return null;

    img.Image processed = original;
    if (processed.width > 1200) {
       processed = img.copyResize(processed, width: 1200);
    }

    processed = img.grayscale(processed);
    processed = img.contrast(processed, contrast: 150);

    return img.encodeJpg(processed);
  }

  Future<void> _loadUiImage(File file) async {
    final data = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    setState(() {
      _uiImage = frame.image;
    });
  }

  Future<void> _cropImage() async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: _currentImage.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Bill',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(
          title: 'Crop Bill',
        ),
      ],
    );

    if (croppedFile != null) {
      setState(() {
        _currentImage = File(croppedFile.path);
        _isFiltered = false; 
        _isScanned = false;
        _extractedText = null;
        _textBlocks = [];
        _uiImage = null;
      });
      _loadUiImage(_currentImage);
    }
  }

  Future<void> _rotateImage() async {
    setState(() => _isProcessing = true);
    try {
      final bytes = await _currentImage.readAsBytes();
      final rotatedBytes = await compute(_rotateImageInIsolate, bytes);
      
      if (rotatedBytes != null) {
        final directory = await getTemporaryDirectory();
        final rotatedPath = '${directory.path}/rotated_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final rotatedFile = File(rotatedPath)..writeAsBytesSync(rotatedBytes);

        setState(() {
          _currentImage = rotatedFile;
          _isScanned = false;
          _extractedText = null;
          _textBlocks = [];
          _uiImage = null;
        });
        _loadUiImage(_currentImage);
      }
    } catch (e) {
      print("Error rotating image: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  static Uint8List? _rotateImageInIsolate(Uint8List bytes) {
    img.Image? original = img.decodeImage(bytes);
    if (original == null) return null;

    if (original.width > 1200) {
       original = img.copyResize(original, width: 1200);
    }
    
    final rotated = img.copyRotate(original, angle: 90);
    return img.encodeJpg(rotated);
  }

  void _toggleDrawingMode() {
    setState(() {
      _isDrawingMode = !_isDrawingMode;
      _drawingPoints = [];
      if (_isDrawingMode) {
        _isScanned = false;
        _extractedText = null;
        _textBlocks = [];
        _roiRect = null; // Reset ROI when starting new drawing
        _activeHandle = null;
      }
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isDrawingMode) return; // Let GestureDetector handle drawing
    if (_roiRect == null || _uiImage == null) return;

    // Check if touching a handle
    final double scale = _lastScale;
    final Rect screenRect = Rect.fromLTRB(
      _roiRect!.left * scale,
      _roiRect!.top * scale,
      _roiRect!.right * scale,
      _roiRect!.bottom * scale,
    );

    final Offset local = event.localPosition;
    const double hitRadius = 30.0;

    int? newHandle;
    if ((local - screenRect.topLeft).distance < hitRadius) {
      newHandle = 0; // TL
    } else if ((local - screenRect.topRight).distance < hitRadius) {
      newHandle = 1; // TR
    } else if ((local - screenRect.bottomLeft).distance < hitRadius) {
      newHandle = 2; // BL
    } else if ((local - screenRect.bottomRight).distance < hitRadius) {
      newHandle = 3; // BR
    }

    if (newHandle != _activeHandle) {
      setState(() {
        _activeHandle = newHandle;
      });
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_activeHandle != null && _roiRect != null) {
      // Resizing ROI
      final double scale = _lastScale;
      final Offset delta = details.delta / scale;
      
      setState(() {
        double left = _roiRect!.left;
        double top = _roiRect!.top;
        double right = _roiRect!.right;
        double bottom = _roiRect!.bottom;

        switch (_activeHandle) {
          case 0: // TL
            left += delta.dx;
            top += delta.dy;
            break;
          case 1: // TR
            right += delta.dx;
            top += delta.dy;
            break;
          case 2: // BL
            left += delta.dx;
            bottom += delta.dy;
            break;
          case 3: // BR
            right += delta.dx;
            bottom += delta.dy;
            break;
        }

        // Enforce min size and bounds
        if (right - left < 20) right = left + 20;
        if (bottom - top < 20) bottom = top + 20;
        
        // Clamp to image bounds
        left = max(0, left);
        top = max(0, top);
        right = min(_uiImage!.width.toDouble(), right);
        bottom = min(_uiImage!.height.toDouble(), bottom);

        _roiRect = Rect.fromLTRB(left, top, right, bottom);
      });
    } else if (_isDrawingMode) {
      // Drawing new ROI
      setState(() {
        _drawingPoints.add(details.localPosition);
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_activeHandle != null) {
      setState(() => _activeHandle = null);
      return;
    }
    
    if (_isDrawingMode && _drawingPoints.length > 3) {
      _setRegionOfInterest();
    }
  }

  void _setRegionOfInterest() {
    if (_uiImage == null || _drawingPoints.isEmpty) return;
    
    // 1. Calculate Bounding Box
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final point in _drawingPoints) {
      minX = min(minX, point.dx);
      minY = min(minY, point.dy);
      maxX = max(maxX, point.dx);
      maxY = max(maxY, point.dy);
    }

    // 2. Convert to Image Coordinates
    final double scale = _lastScale;
    final double roiX = minX / scale;
    final double roiY = minY / scale;
    final double roiW = (maxX - minX) / scale;
    final double roiH = (maxY - minY) / scale;

    setState(() {
      _roiRect = Rect.fromLTWH(roiX, roiY, roiW, roiH);
      _isDrawingMode = false; // Exit drawing mode
      _drawingPoints = [];
    });
  }

  static Uint8List? _cropImageInIsolate(List<dynamic> args) {
      final Uint8List bytes = args[0];
      final int x = args[1];
      final int y = args[2];
      final int w = args[3];
      final int h = args[4];
      
      img.Image? original = img.decodeImage(bytes);
      if (original == null) return null;
      
      // Ensure bounds
      final int safeX = max(0, x);
      final int safeY = max(0, y);
      final int safeW = min(w, original.width - safeX);
      final int safeH = min(h, original.height - safeY);
      
      if (safeW <= 0 || safeH <= 0) return null;

      final cropped = img.copyCrop(original, x: safeX, y: safeY, width: safeW, height: safeH);
      
      // Upscale if too small (Tesseract needs good resolution)
      img.Image processed = cropped;
      if (processed.width < 1000) {
        // Scale up to at least 1000px width, maintaining aspect ratio
        final double scale = 1000 / processed.width;
        if (scale > 1.0) {
           processed = img.copyResize(processed, width: 1000, interpolation: img.Interpolation.cubic);
        }
      }
      
      // Enhance for OCR
      processed = img.grayscale(processed);
      processed = img.contrast(processed, contrast: 120); // Boost contrast
      // processed = img.adjustColor(processed, saturation: 0); // Ensure grayscale

      return img.encodeJpg(processed, quality: 100);
  }

  Future<void> _performScan() async {
    setState(() => _isProcessing = true);
    try {
      File scanFile = _currentImage;
      
      // If ROI is set, CROP the image permanently for this scan
      if (_roiRect != null) {
        final bytes = await _currentImage.readAsBytes();
        final croppedBytes = await compute(_cropImageInIsolate, [
          bytes, 
          _roiRect!.left.toInt(), 
          _roiRect!.top.toInt(), 
          _roiRect!.width.toInt(), 
          _roiRect!.height.toInt()
        ]);
        
        if (croppedBytes != null) {
           final directory = await getTemporaryDirectory();
           final croppedPath = '${directory.path}/cropped_scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
           final croppedFile = File(croppedPath)..writeAsBytesSync(croppedBytes);
           
           // Update current image to the cropped one
           scanFile = croppedFile;
           
           if (mounted) {
             setState(() {
               _currentImage = croppedFile;
               _roiRect = null; // Clear ROI since we are now looking at the cropped image
               _uiImage = null; // Force reload of UI image
             });
             await _loadUiImage(_currentImage);
           }
        }
      }

      // Run Text extraction first (Priority for accuracy)
      // Restoring exact args from the "good" state
      final String plainText = await FlutterTesseractOcr.extractText(
        scanFile.path, 
        language: 'tha+eng',
        args: {
          "psm": "4",
          "preserve_interword_spaces": "1",
          "tessedit_create_tsv": "1", // User reported this config worked best
        }
      );

      print("DEBUG: OCR Output Content: $plainText");

      // Then run HOCR for bounding boxes (Visual only)
      String hocrOutput = "";
      try {
        hocrOutput = await FlutterTesseractOcr.extractHocr(
          scanFile.path, 
          language: 'tha+eng',
          args: {
            "psm": "4",
            "preserve_interword_spaces": "1",
          }
        );
      } catch (e) {
        print("DEBUG: HOCR extraction failed: $e");
      }

      print("DEBUG: HOCR Output Length: ${hocrOutput.length}");
      
      // Parse HOCR for bounding boxes
      final blocks = _parseHocr(hocrOutput);
      
      // No need to offset blocks anymore because we cropped the image!
      setState(() {
        _textBlocks = blocks;
        _extractedText = plainText;
        _isScanned = true;
      });
      
    } catch (e) {
      print("OCR Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("OCR Failed: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  List<TesseractBlock> _parseTsv(String tsv) {
    return [];
  }

  // Helper class for parsing result
  HocrResult _parseHocrAndText(String hocr) {
    // Deprecated
    return HocrResult([], "");
  }

  List<TesseractBlock> _parseHocr(String hocr) {
    final List<TesseractBlock> blocks = [];
    final RegExp wordRegExp = RegExp(r"<span class='ocrx_word'[^>]*title='bbox (\d+) (\d+) (\d+) (\d+); x_wconf (\d+)'[^>]*>(.*?)</span>");
    
    final matches = wordRegExp.allMatches(hocr);
    for (final match in matches) {
      try {
        final left = double.parse(match.group(1)!);
        final top = double.parse(match.group(2)!);
        final right = double.parse(match.group(3)!);
        final bottom = double.parse(match.group(4)!);
        final conf = int.parse(match.group(5)!);
        final text = match.group(6)!;

        if (conf > 30 && text.trim().isNotEmpty) {
           blocks.add(TesseractBlock(
             rect: Rect.fromLTRB(left, top, right, bottom),
             text: text,
             confidence: conf,
           ));
        }
      } catch (e) {
        print("Error parsing HOCR match: $e");
      }
    }
    return blocks;
  }

  void _confirmAndReturn() {
    if (_extractedText != null) {
      Navigator.pop(context, _extractedText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text("Adjust Image"),
        actions: [
          if (_isScanned)
            TextButton(
              onPressed: _confirmAndReturn,
              child: const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
            )
          else
            TextButton(
              onPressed: _isProcessing ? null : _performScan,
              child: const Text("SCAN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _isProcessing 
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text("Processing...", style: TextStyle(color: Colors.white)),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (_uiImage == null) {
                          return Image.file(_currentImage, fit: BoxFit.contain);
                        }
                        
                        // Calculate scale to fit image in screen while maintaining aspect ratio
                        final double scaleX = constraints.maxWidth / _uiImage!.width;
                        final double scaleY = constraints.maxHeight / _uiImage!.height;
                        final double scale = scaleX < scaleY ? scaleX : scaleY;
                        
                        final double fittedWidth = _uiImage!.width * scale;
                        final double fittedHeight = _uiImage!.height * scale;

                        _lastScale = scale; // Store scale for drawing conversion

                        return InteractiveViewer(
                          maxScale: 5.0,
                          panEnabled: !_isDrawingMode && _activeHandle == null,
                          scaleEnabled: !_isDrawingMode && _activeHandle == null,
                          child: Center(
                            child: Listener(
                              onPointerDown: _handlePointerDown,
                              child: GestureDetector(
                                onPanUpdate: (_isDrawingMode || _activeHandle != null) ? _handlePanUpdate : null,
                                onPanEnd: (_isDrawingMode || _activeHandle != null) ? _handlePanEnd : null,
                                child: SizedBox(
                                width: fittedWidth,
                                height: fittedHeight,
                                child: Stack(
                                  children: [
                                    Image.file(
                                      _currentImage,
                                      fit: BoxFit.contain,
                                      width: fittedWidth,
                                      height: fittedHeight,
                                    ),
                                    if (_roiRect != null)
                                      CustomPaint(
                                        painter: RoiPainter(_roiRect!, _uiImage!),
                                        size: Size(fittedWidth, fittedHeight),
                                      ),
                                    if (_isScanned)
                                      CustomPaint(
                                        painter: TesseractOverlayPainter(_textBlocks, _uiImage!),
                                        size: Size(fittedWidth, fittedHeight),
                                      ),
                                    if (_isDrawingMode)
                                      CustomPaint(
                                        painter: DrawingPainter(_drawingPoints),
                                        size: Size(fittedWidth, fittedHeight),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );

                      },
                    ),
            ),
          ),
          // Show preview of text if scanned
          if (_isScanned && _extractedText != null)
            Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              height: 100,
              child: SingleChildScrollView(
                child: Text(
                  _extractedText!, 
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildToolButton(Icons.crop, "Crop", _cropImage),
          _buildToolButton(Icons.rotate_right, "Rotate", _rotateImage),
          _buildToolButton(
            _isDrawingMode ? Icons.edit_off : Icons.edit, 
            _isDrawingMode ? "Cancel" : "Draw", 
            _toggleDrawingMode
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: _isProcessing ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

class HocrResult {
  final List<TesseractBlock> blocks;
  final String fullText;

  HocrResult(this.blocks, this.fullText);
}

class TesseractBlock {
  final Rect rect;
  final String text;
  final int confidence;

  TesseractBlock({required this.rect, required this.text, required this.confidence});
}

class TesseractOverlayPainter extends CustomPainter {
  final List<TesseractBlock> blocks;
  final ui.Image image;

  TesseractOverlayPainter(this.blocks, this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.greenAccent;

    // Calculate scale factors
    final double scaleX = size.width / image.width;
    final double scaleY = size.height / image.height;

    for (final block in blocks) {
      final rect = block.rect;
      final scaledRect = Rect.fromLTRB(
        rect.left * scaleX,
        rect.top * scaleY,
        rect.right * scaleX,
        rect.bottom * scaleY,
      );
      
      // Draw Box Only (No Text)
      canvas.drawRect(scaledRect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(TesseractOverlayPainter oldDelegate) {
    return oldDelegate.blocks != blocks;
  }
}

class DrawingPainter extends CustomPainter {
  final List<Offset> points;
  DrawingPainter(this.points);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
      
    for (int i = 0; i < points.length - 1; i++) {
      if ((points[i] - points[i+1]).distance < 50) { // Simple filter for jumps
        canvas.drawLine(points[i], points[i+1], paint);
      }
    }
  }
  
  @override
  bool shouldRepaint(DrawingPainter old) => old.points.length != points.length;
}



class RoiPainter extends CustomPainter {
  final Rect roiRect;
  final ui.Image image;
  
  RoiPainter(this.roiRect, this.image);
  
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
      
    final Paint handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
      
    final Paint handleBorder = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final double scaleX = size.width / image.width;
    final double scaleY = size.height / image.height;

    final scaledRect = Rect.fromLTRB(
      roiRect.left * scaleX,
      roiRect.top * scaleY,
      roiRect.right * scaleX,
      roiRect.bottom * scaleY,
    );
    
    // Draw Box
    canvas.drawRect(scaledRect, paint);
    
    // Draw Handles
    const double handleSize = 12.0;
    final List<Offset> handles = [
      scaledRect.topLeft,
      scaledRect.topRight,
      scaledRect.bottomLeft,
      scaledRect.bottomRight,
    ];
    
    for (final handle in handles) {
      canvas.drawCircle(handle, handleSize / 2, handlePaint);
      canvas.drawCircle(handle, handleSize / 2, handleBorder);
    }
  }
  
  @override
  bool shouldRepaint(RoiPainter old) => old.roiRect != roiRect;
}
