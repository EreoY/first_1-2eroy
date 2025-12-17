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
  File? _processedOriginalImage; // To restore after reset
  bool _isProcessing = false;
  bool _isFiltered = false;
  
  // Scan State
  String? _extractedText; // For final return
  ui.Image? _uiImage; // For scaling coordinates
  bool _isScanned = false;
  
  // Drawing State
  bool _isDrawingMode = true; // Default to drawing mode for "Circle to Search" feel
  List<Offset> _drawingPoints = [];
  Rect? _roiRect; // Region of Interest in Image Coordinates
  int? _activeHandle; // 0: TL, 1: TR, 2: BL, 3: BR, null: None
  double _lastScale = 1.0; // To convert screen coords to image coords
  
  // Animation State

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
            if (auto) _processedOriginalImage = filteredFile; // Save the pristine processed version
            _isFiltered = true;
            _isScanned = false; // Reset scan state
            _extractedText = null;
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

  final TransformationController _transformationController = TransformationController();
  bool _needsCentering = true;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // ... (existing initState)

  Future<void> _loadUiImage(File file) async {
    final data = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _uiImage = frame.image;
        _needsCentering = true; // Trigger centering on next build
      });
    }
  }

  // ... (existing methods)



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
    
    if (_isDrawingMode && _drawingPoints.length > 5) {
      _finishCircleSelection();
    } else {
        // Tap or too short drag - clear
        setState(() {
            _drawingPoints = [];
        });
    }
  }

  void _finishCircleSelection() {
     _setRegionOfInterest();
     // Auto-scan after a short delay to let the user see the visual feedback
     if (_roiRect != null) {
        Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && !_isProcessing) {
                _performScan();
            }
        });
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
      _isDrawingMode = false; // Exit drawing mode temporarily to show result
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

      // Removed HOCR (Bounding Boxes) per user request to optimize performance.
      // "No need to scan to circle the text" -> Single Pass Only.
      
      setState(() {
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

  // Removed unused OCR helpers


  void _confirmAndReturn() {
    if (_extractedText != null) {
      Navigator.pop(context, _extractedText);
    }
  }

  void _resetScan() {
    setState(() {
      _isDrawingMode = true; // Back to Circle mode
      _roiRect = null;
      _isScanned = false;
      _extractedText = null;
      _drawingPoints = [];
      _needsCentering = true;
    });
    
    // Restoration Logic
    if (_processedOriginalImage != null) {
        // If we have the auto-processed image (grayscale), revert to THAT.
        // This keeps the "enhanced" look the user likes.
        setState(() {
            _currentImage = _processedOriginalImage!;
        });
    } else {
        // Fallback to raw if logic failed
        setState(() {
            _currentImage = widget.imageFile;
        });
    }
    
    _loadUiImage(_currentImage);
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
              child: const Text("SCAN NOW", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            )
        ],
      ),
      body: Stack(
        children: [
            // Layer 1: Image Viewer (Always at bottom)
            Positioned.fill(
                child: _isProcessing 
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text("Processing...", style: TextStyle(color: Colors.white)),
                        ],
                      )
                    )
                      : LayoutBuilder(
                      builder: (context, constraints) {
                        if (_uiImage == null) {
                          return Center(child: Image.file(_currentImage, fit: BoxFit.contain));
                        }
                        
                        final double scaleX = constraints.maxWidth / _uiImage!.width;
                        final double scaleY = constraints.maxHeight / _uiImage!.height;
                        final double scale = scaleX < scaleY ? scaleX : scaleY;
                        
                        final double fittedWidth = _uiImage!.width * scale;
                        final double fittedHeight = _uiImage!.height * scale;

                        _lastScale = scale; 

                        if (_needsCentering) {
                          _needsCentering = false;
                          final double dx = (constraints.maxWidth - fittedWidth) / 2;
                          final double dy = (constraints.maxHeight - fittedHeight) / 2;

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                  _transformationController.value = Matrix4.translationValues(dx, dy, 0);
                              }
                          });
                        }

                      return InteractiveViewer(
                          transformationController: _transformationController,
                          minScale: 1.0,
                          maxScale: 5.0,
                          panEnabled: !_isDrawingMode && _activeHandle == null,
                          scaleEnabled: !_isDrawingMode && _activeHandle == null,
                          boundaryMargin: EdgeInsets.all(max(constraints.maxWidth, constraints.maxHeight)), // Allow ample space
                          constrained: false, // Allow manual positioning
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
                                    // Spotlight overlay
                                    if (_roiRect != null)
                                        CustomPaint(
                                            painter: SpotlightOverlayPainter(
                                                roiRect: _roiRect,
                                                image: _uiImage!,
                                                drawingPoints: _drawingPoints
                                            ),
                                            size: Size(fittedWidth, fittedHeight),
                                        ),
                                    if (_roiRect != null)
                                      CustomPaint(
                                        painter: RoiPainter(_roiRect!, _uiImage!),
                                        size: Size(fittedWidth, fittedHeight),
                                      ),
                                    if (_isDrawingMode)
                                      CustomPaint(
                                        painter: GlowingPathPainter(_drawingPoints),
                                        size: Size(fittedWidth, fittedHeight),
                                      ),
                                    // Hint Text
                                    if (_isDrawingMode && _drawingPoints.isEmpty && _roiRect == null)
                                        Positioned(
                                            top: 20,
                                            left: 0,
                                            right: 0,
                                            child: Center(
                                                child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                    decoration: BoxDecoration(
                                                        color: Colors.black.withValues(alpha: 0.6),
                                                        borderRadius: BorderRadius.circular(20)
                                                    ),
                                                    child: const Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                            Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 16),
                                                            SizedBox(width: 8),
                                                            Text("Circle to Search", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                        ],
                                                    )
                                                )
                                            ),
                                        ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );

                      },
                    ),
            ),
            
            // Layer 2: Bottom Bar (Only visible when NOT scanned to allow access back to reset)
            if (!_isScanned)
                Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomBar(),
                ),

            // Layer 3: Draggable Text Card (Only when scanned)
            if (_isScanned && _extractedText != null)
                DraggableScrollableSheet(
                    initialChildSize: 0.5,
                    minChildSize: 0.4, // Increased to prevent overflow/squeeze
                    maxChildSize: 0.9,
                    builder: (context, scrollController) {
                        return Container(
                            decoration: const BoxDecoration(
                                color: Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                boxShadow: [
                                    BoxShadow(
                                        color: Colors.black54,
                                        blurRadius: 10,
                                        offset: Offset(0, -5),
                                    )
                                ]
                            ),
                            child: SingleChildScrollView(
                              controller: scrollController, // Attached here!
                              child: Column(
                                mainAxisSize: MainAxisSize.min, // Important
                                children: [
                                    // Handle
                                    Center(
                                        child: Container(
                                            margin: const EdgeInsets.only(top: 12, bottom: 8),
                                            width: 40,
                                            height: 4,
                                            decoration: BoxDecoration(
                                                color: Colors.grey[600],
                                                borderRadius: BorderRadius.circular(2)
                                            ),
                                        ),
                                    ),
                                    // Header
                                    Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                        child: Row(
                                            children: [
                                                const Icon(Icons.text_fields, color: Colors.blueAccent),
                                                const SizedBox(width: 8),
                                                const Text(
                                                    "Extracted Text", 
                                                    style: TextStyle(
                                                        color: Colors.white, 
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 18
                                                    )
                                                ),
                                                const Spacer(),
                                                // Reset Button (in case they want to scan again)
                                                IconButton(
                                                    icon: const Icon(Icons.refresh, color: Colors.grey),
                                                    onPressed: _resetScan,
                                                )
                                            ],
                                        ),
                                    ),
                                    const Divider(color: Colors.grey, height: 1),
                                    
                                    // Content Text
                                    Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Text(
                                                _extractedText!,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    height: 1.5,
                                                ),
                                        ),
                                    ),

                                    // Confirm Button Area
                                    Container(
                                        padding: const EdgeInsets.all(16),
                                        color: Colors.black12,
                                        child: SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton(
                                                onPressed: _confirmAndReturn,
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.greenAccent,
                                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                                    shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(12)
                                                    )
                                                ),
                                                child: const Text("USE THIS TEXT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                            ),
                                        ),
                                    ),
                                    // Add extra padding at bottom if needed
                                    const SizedBox(height: 20),
                                ],
                              ),
                            ),
                        );
                    },
                ),
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
          _buildToolButton(Icons.restart_alt, "Reset", _resetScan),
          _buildToolButton(Icons.rotate_right, "Rotate", _rotateImage),
          _buildToolButton(
            _isDrawingMode ? Icons.auto_awesome : Icons.edit_outlined, 
            "Circle", 
            _toggleDrawingMode
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: _isProcessing ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            color: label == "Circle" && _isDrawingMode ? const Color(0xFF333333) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: label == "Circle" && _isDrawingMode ? Colors.blueAccent : Colors.white),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
                color: label == "Circle" && _isDrawingMode ? Colors.blueAccent : Colors.white, 
                fontSize: 12,
                fontWeight: label == "Circle" && _isDrawingMode ? FontWeight.bold : FontWeight.normal
            )),
          ],
        ),
      ),
    );
  }
}

// ... helper classes ...

class SpotlightOverlayPainter extends CustomPainter {
    final Rect? roiRect;
    final ui.Image image;
    final List<Offset> drawingPoints;

    SpotlightOverlayPainter({this.roiRect, required this.image, required this.drawingPoints});

    @override
    void paint(Canvas canvas, Size size) {
        final double scaleX = size.width / image.width;
        final double scaleY = size.height / image.height;

        final Paint darkPaint = Paint()
            ..color = Colors.black.withOpacity(0.6)
            ..style = PaintingStyle.fill;

        // Base Layer: Darken everything
        // canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), darkPaint);
        // We need to cut out the hole.
        
        // Complex path for hole
        final Path backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
        Path cutoutPath = Path();

        if (roiRect != null) {
            final scaledRect = Rect.fromLTRB(
                roiRect!.left * scaleX,
                roiRect!.top * scaleY,
                roiRect!.right * scaleX,
                roiRect!.bottom * scaleY,
            );
             cutoutPath.addRect(scaledRect);
        } else if (drawingPoints.isNotEmpty) {
           // If drawing, maybe don't darken yet? Or darken outside the polygon?
           // For simplicity, let's only darken when ROI is settled or not darken at all during draw
           return; 
        } else {
            // No ROI, no Drawing -> No spotlight or everything dark? 
            // Let's keep it clear until user interacts
            return;
        }

        final Path finalPath = Path.combine(
            PathOperation.difference,
            backgroundPath,
            cutoutPath,
        );

        canvas.drawPath(finalPath, darkPaint);
    }

    @override
    bool shouldRepaint(covariant SpotlightOverlayPainter oldDelegate) {
        return oldDelegate.roiRect != roiRect || oldDelegate.drawingPoints.length != drawingPoints.length;
    }
}

class GlowingPathPainter extends CustomPainter {
  final List<Offset> points;
  
  GlowingPathPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // 1. Outer Glow
    final Paint glowPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.6)
      ..strokeWidth = 12.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    // 2. Core Line
    final Paint corePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.cyanAccent, Colors.purpleAccent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path path = Path();
    if (points.isNotEmpty) {
        path.moveTo(points[0].dx, points[0].dy);
        for (int i = 1; i < points.length; i++) {
             // Smooth curves
             // path.lineTo(points[i].dx, points[i].dy);
             if (i < points.length - 1) {
                final p0 = points[i];
                final p1 = points[i + 1];
                path.quadraticBezierTo(
                    p0.dx, p0.dy, 
                    (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2
                );
             }
        }
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, corePaint);
  }

  @override
  bool shouldRepaint(GlowingPathPainter old) => old.points.length != points.length;
}

// HocrResult, TesseractBlock, TesseractOverlayPainter Removed





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
