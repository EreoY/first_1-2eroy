import 'dart:io';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'image_processor_service.dart';
import 'scan_history_service.dart';
import 'ai_service.dart';

class SlipData {
  final String bank;
  final double amount;
  final DateTime date;
  final String? memo;
  final String? recipient; // Extracted Shop/Recipient Name
  final String? category; // ML/LLM Classified Category
  final String? slipImagePath; // Path to the original image file

  SlipData({
    required this.bank, 
    required this.amount, 
    required this.date, 
    this.memo, 
    this.recipient,
    this.category,
    this.slipImagePath,
  });

  @override
  String toString() => 'SlipData(bank: $bank, amount: $amount, date: $date, category: $category, recipient: $recipient, path: $slipImagePath)';
  
  Map<String, dynamic> toMap() {
    return {
      'bank': bank,
      'amount': amount,
      'date': date.toIso8601String(),
      'memo': memo,
      'recipient': recipient,
      'category': category,
      'slipImagePath': slipImagePath,
    };
  }
}

class SlipScannerService {
  final ScanHistoryService _historyService = ScanHistoryService();
  final ImageProcessorService _imageProcessor = ImageProcessorService();
  final AIService _aiService = AIService();

  Future<List<File>> fetchNewSlipFiles({bool isManual = false}) async {
    // print("[SlipScanner] Starting Smart Fetch... (Manual: $isManual)");

    // ...

    // print("[SlipScanner] Time Window: $startDateTime to $endDateTime (Scanning Oldest First)");

    // ...

    // print("[SlipScanner] Scanning ${albums.length} albums: ${albums.map((a) => a.name).toList()}");

    // ...

    // print("[SlipScanner] Album '${album.name}': Found $assetCount new assets (Fetched top $fetchCount)");

    // ...

    // print("[SlipScanner] Global Sort: Processing ${sortedAssets.length} unique assets...");

    // ...

    // print("[SlipScanner] Fetch complete. Found ${foundFiles.length} new files.");
    
    // 1. Check Permissions
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      print("[SlipScanner] Permission denied");
      return [];
    }

    // 2. Determine Time Window
    final scannedFileIds = await _historyService.getScannedFileIds();
    final selectedAlbumIds = await _historyService.getSelectedAlbumIds();
    
    final DateTime endDateTime = DateTime.now();
    DateTime startDateTime;

    if (isManual) {
      // Manual Scan: User wants to re-check last 30 days
      startDateTime = endDateTime.subtract(const Duration(days: 30));
      print("[SlipScanner] Manual Scan Mode: Re-checking last 30 days.");
    } else {
      // Auto Scan: Incremental from last checkpoint
      if (selectedAlbumIds.isEmpty) {
         startDateTime = await _historyService.getCutoffDate('global_recent');
      } else {
         DateTime minDate = endDateTime;
         bool first = true;
         for (final id in selectedAlbumIds) {
           final date = await _historyService.getCutoffDate(id);
           if (first || date.isBefore(minDate)) {
             minDate = date;
             first = false;
           }
         }
         startDateTime = minDate;
      }
      print("[SlipScanner] Auto Scan Mode: Incremental from $startDateTime");
    }

    print("[SlipScanner] Time Window: $startDateTime to $endDateTime (Scanning Oldest First)");

    // 3. Configure PhotoManager Filter (Database Level)
    final FilterOptionGroup option = FilterOptionGroup(
      // User Request: Sort Oldest -> Newest
      orders: [
        OrderOption(type: OrderOptionType.createDate, asc: true),
      ],
      // Date Filtering at DB Level
      createTimeCond: DateTimeCond(
        min: startDateTime,
        max: endDateTime,
      ),
    );

    // 4. Fetch Albums with Filter
    // This returns only albums that contain assets matching the filter
    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: option,
    );

    // Filter by selected albums if needed
    if (selectedAlbumIds.isNotEmpty) {
      albums = albums.where((a) => selectedAlbumIds.contains(a.id)).toList();
    } else {
      // If "Recent" mode, usually we just want the "Recent" album (first one)
      // But scanning all albums that have new photos is also valid and safer.
      // Let's stick to the user's previous preference: "Recent" usually means the aggregate album.
      if (albums.isNotEmpty) {
         // Find the "Recent" album (usually isAll is true)
         final recentAlbum = albums.firstWhere((a) => a.isAll, orElse: () => albums.first);
         albums = [recentAlbum];
      }
    }

    if (albums.isEmpty) {
      print("[SlipScanner] No albums found with new images.");
      return [];
    }

    print("[SlipScanner] Scanning ${albums.length} albums: ${albums.map((a) => a.name).toList()}");

    List<AssetEntity> allAssets = [];
    List<File> foundFiles = [];
    List<String> newScannedIds = [];

    try {
      // 5. Collect Assets from All Albums
      for (final album in albums) {
        final int assetCount = await album.assetCountAsync;
        if (assetCount == 0) continue;

        final int fetchCount = assetCount > 500 ? 500 : assetCount;
        final assets = await album.getAssetListRange(start: 0, end: fetchCount);

        print("[SlipScanner] Album '${album.name}': Found $assetCount new assets (Fetched top $fetchCount)");
        allAssets.addAll(assets);
        
        // Update checkpoint for this album immediately as we have "scanned" it
        if (selectedAlbumIds.contains(album.id)) {
           await _historyService.updateLastScanTime(album.id);
        }
      }

      // 6. Deduplicate & Sort Globally (Oldest -> Newest)
      // Use a Map to deduplicate by ID
      final Map<String, AssetEntity> uniqueAssetsMap = {};
      for (final asset in allAssets) {
        uniqueAssetsMap[asset.id] = asset;
      }
      final List<AssetEntity> sortedAssets = uniqueAssetsMap.values.toList();
      
      // Sort: Ascending (Oldest First)
      sortedAssets.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));
      
      print("[SlipScanner] Global Sort: Processing ${sortedAssets.length} unique assets...");

      // 7. Convert to Files
      for (final asset in sortedAssets) {
          // Double check "Mark as Read" (Safety net)
          if (scannedFileIds.contains(asset.id)) {
            continue; 
          }

          File? file = await asset.file;
          if (file == null) continue;

          // Add to list (Processing will be done by Provider to show UI feedback)
          foundFiles.add(file);
          newScannedIds.add(asset.id);
      }
      
      // Update global checkpoint if in Recent mode
      if (selectedAlbumIds.isEmpty) {
        await _historyService.updateLastScanTime('global_recent');
      }

    } finally {
      // Save new scanned IDs
      if (newScannedIds.isNotEmpty) {
        await _historyService.addScannedFileIds(newScannedIds);
        print("[SlipScanner] Marked ${newScannedIds.length} files as read.");
      }
    }

    print("[SlipScanner] Fetch complete. Found ${foundFiles.length} new files.");
    return foundFiles;
  }

  Future<SlipData?> processImageFile(File file) async {
    print("[DEBUG_IMAGE_PATH] Processing file: ${file.path}");

    // Pre-process Image
    final processedPath = await _imageProcessor.processForOCR(file);

    // Tesseract OCR
    // args: psm 4 = Assume a single column of text of variable sizes.
    // preserve_interword_spaces = 1 to keep spacing.
    final String text = await FlutterTesseractOcr.extractText(
      processedPath, 
      language: 'tha+eng',
      args: {
        "psm": "4",
        "preserve_interword_spaces": "1",
      }
    );

    print("--------------------------------------------------");
    print("[DEBUG_RAW_TEXT] START");
    print(text);
    print("[DEBUG_RAW_TEXT] END");
    print("--------------------------------------------------");

    // 1. Detect Amount (Critical)
    print("[DEBUG_LOGIC] Attempting to detect Amount (Aggressive)...");
    double? amount = _detectAmount(text);
    
    if (amount == null) {
      print("[DEBUG_LOGIC] Amount detection FAILED for file: ${file.path}");
      print("[DEBUG_FAILURE_CONTEXT] Raw Text was:\n$text\n[END RAW TEXT]");
      return null; // Cannot proceed without amount
    }
    print("[DEBUG_LOGIC] Amount Detected: $amount");

    // 2. Detect Bank (Thai Keywords)
    print("[DEBUG_LOGIC] Attempting to detect Bank...");
    String bank = _detectBankThai(text);
    print("[DEBUG_LOGIC] Bank Detected: $bank");

    // 3. Detect Recipient / Shop Name (Dynamic Anchors)
    print("[DEBUG_LOGIC] Attempting to extract Recipient/Shop Name...");
    String? recipient = _extractRecipientName(text);
    if (recipient != null) print("[DEBUG_LOGIC] Recipient Detected: $recipient");

    // 4. Detect Memo (Disabled per user request)
    String? memo; 

    // 5. Categorize (using Local LLM)
    String? category;
    if (recipient != null) {
      print("[DEBUG_LOGIC] Categorizing recipient: '$recipient' ...");
      // Critical: Send ONLY the recipient name, NOT the full text
      category = await _aiService.predictCategory(recipient);
      print("[DEBUG_LOGIC] Category predicted: $category");
    } else {
      category = "อื่นๆ"; // Fallback if no recipient name
    }

    // Date: Use file modification time as proxy
    DateTime date = await file.lastModified();
    print("[DEBUG_LOGIC] Date extracted (from file): $date");

    final slip = SlipData(
      bank: bank, 
      amount: amount, 
      date: date, 
      memo: memo, 
      recipient: recipient, 
      category: category,
      slipImagePath: file.path, // Store the path!
    );
    print("[DEBUG_FINAL_OBJECT] Created SlipData: $slip");
    return slip;
  }

  String _detectBankThai(String text) {
    final lowerText = text.toLowerCase();
    
    // Kasikorn
    if (text.contains('กสิกร') || lowerText.contains('kbank') || lowerText.contains('kasikorn')) {
      return 'Kasikorn Bank';
    }

    // SCB
    if (text.contains('ไทยพาณิชย์') || lowerText.contains('scb') || lowerText.contains('siam commercial')) {
      return 'SCB';
    }

    // Krungthai
    if (text.contains('กรุงไทย') || lowerText.contains('krungthai') || lowerText.contains('ktb')) {
      return 'Krungthai Bank';
    }

    // Bangkok Bank
    if (text.contains('กรุงเทพ') || lowerText.contains('bbl') || lowerText.contains('bangkok bank')) {
      return 'Bangkok Bank';
    }

    // GSB
    if (text.contains('ออมสิน') || text.contains('ธนาคารออมสิน') || lowerText.contains('gsb') || lowerText.contains('mymo')) {
      return 'GSB';
    }
    
    // TTB
    if (text.contains('ทหารไทย') || text.contains('ธนชาต') || lowerText.contains('ttb')) {
      return 'TTB';
    }

    // TrueMoney
    if (text.contains('ทรูมันนี่') || lowerText.contains('truemoney') || lowerText.contains('true')) {
      return 'TrueMoney Wallet';
    }

    // 7-Eleven
    if (text.contains('7-Eleven') || text.contains('CPALL')) {
      return '7-Eleven';
    }

    return 'Unknown Slip';
  }

  String? _extractRecipientName(String text) {
    final lines = text.split('\n').map((l) => l.trim()).toList();

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      // 1. Direct match (e.g., "To: Mr. A")
      final directMatch = RegExp(r'(?:ถึง|ไปยัง|To|Sent to)\s*[:]?\s*(.+)').firstMatch(line);
      if (directMatch != null && directMatch.group(1)!.trim().isNotEmpty) {
        return _cleanRecipientName(directMatch.group(1)!.trim());
      }

      // 2. Multi-line match (Keyword is on one line, Name is on the next)
      // Example: 
      // "To"
      // "7-Eleven"
      if (RegExp(r'^(ถึง|ไปยัง|To|Sent to)$').hasMatch(line)) {
        // Check next line
        if (i + 1 < lines.length && lines[i+1].isNotEmpty) {
           return _cleanRecipientName(lines[i+1]);
        }
        // Check skip-one line (in case of empty gap)
        if (i + 2 < lines.length && lines[i+2].isNotEmpty) {
           return _cleanRecipientName(lines[i+2]);
        }
      }
      
      // 3. Special Case for TrueMoney / Wallets
      if (line.contains('จากวอลเล็ท') || line.contains('From Wallet')) {
         // Search 3 lines below for a likely name candidate
         for (int j = 1; j <= 3 && i + j < lines.length; j++) {
           String candidate = lines[i + j];
           // Heuristic: Name often starts with Title or is long enough
           if (candidate.startsWith('นาย') || candidate.startsWith('นาง') || candidate.startsWith('น.s.') || candidate.length > 5) {
             return _cleanRecipientName(candidate);
           }
         }
      }
    }
    return null;
  }

  String _cleanRecipientName(String raw) {
    // Remove garbage characters from the start
    // ษ์, Ww, ©, +, |
    String cleaned = raw.replaceAll(RegExp(r'^[ษ์Ww©+|]+'), '').trim();
    return cleaned;
  }

  double? _detectAmount(String text) {
    print("[DEBUG_REGEX] Scanning for aggressive amount patterns...");
    
    final lines = text.split('\n');
    
    // 1. Aggressive Standalone Price Search
    // Pattern: ^[\d,]+\.\d{2}$ (e.g., 50.00, 1,200.50)
    // It must be the ONLY thing on the line (after trimming)
    final aggressiveRegex = RegExp(r'^[\d,]+\.\d{2}$');
    // Pattern for TrueMoney: B 6.00 (Relaxed)
    final trueMoneyRegex = RegExp(r'[B฿]\s*([\d,]+\.\d{2})');

    for (var line in lines) {
      final trimmed = line.trim();
      if (aggressiveRegex.hasMatch(trimmed)) {
        print("[DEBUG_REGEX] Found Aggressive Match: '$trimmed'");
        final amount = _extractNumber(trimmed);
        if (amount != null) return amount;
      }
      
      // Check TrueMoney pattern
      final tmMatch = trueMoneyRegex.firstMatch(trimmed);
      if (tmMatch != null) {
        print("[DEBUG_REGEX] Found TrueMoney Match: '$trimmed'");
        final amountStr = tmMatch.group(1);
        if (amountStr != null) {
          final amount = _extractNumber(amountStr);
          if (amount != null) return amount;
        }
      }
    }

    // 2. Keyword Fallback (Amount, จำนวน, etc.)
    print("[DEBUG_REGEX] No aggressive match. Trying keywords...");
    for (var line in lines) {
      if (line.toLowerCase().contains('amount') || line.contains('จำนวน') || line.contains('บาท')) {
        print("[DEBUG_REGEX] Found keyword in line: '$line'");
        final amount = _extractNumber(line);
        if (amount != null) {
           print("[DEBUG_REGEX] Match Found via Keyword: $amount");
           return amount;
        }
      }
    }

    return null;
  }

  double? _extractNumber(String line) {
    // Remove commas
    final cleanLine = line.replaceAll(',', '');
    // Regex to find floating point numbers
    final RegExp regex = RegExp(r'(\d+\.\d{2})');
    final match = regex.firstMatch(cleanLine);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  String? _detectMemo(String text) {
    final lines = text.split('\n');
    for (var line in lines) {
      if (line.contains('บันทึกช่วยจำ') || line.toLowerCase().contains('note') || line.toLowerCase().contains('ref')) {
        // Return the whole line or maybe strip the label
        return line.trim();
      }
    }
    return null;
  }
}
