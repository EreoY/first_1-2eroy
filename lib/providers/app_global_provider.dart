import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/ai_service.dart';
import '../services/slip_scanner_service.dart';
import '../services/scan_history_service.dart';
import '../services/database_service.dart';
import '../models/chat_message.dart';

import 'dart:async'; // Add async import for Timer

class AppGlobalProvider extends ChangeNotifier with WidgetsBindingObserver {
  final AIService _aiService = AIService();
  final SlipScannerService _scannerService = SlipScannerService();
  final ScanHistoryService _historyService = ScanHistoryService();

  bool _isAIModelLoaded = false;
  bool get isAIModelLoaded => _isAIModelLoaded;

  List<SlipData> _pendingSlips = [];
  List<SlipData> get pendingSlips => _pendingSlips;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  Timer? _scanTimer;

  Future<void> initialize() async {
    print("[AppGlobalProvider] Initializing...");
    
    // 0. Register Lifecycle Observer
    WidgetsBinding.instance.addObserver(this);
    
    // 1. Initialize AI (Background)
    _initAI();

    // 2. Auto-Scan Slips (Using "Button" Logic)
    // We delay slightly to ensure DB is ready if needed, though Hive should be ready by now.
    Future.delayed(const Duration(seconds: 1), () {
      scanSlips(); 
    });

    // 3. Periodic Scan (Every 60 Seconds)
    _scanTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      print("[AppGlobalProvider] Periodic Scan Triggered");
      scanSlips();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("[AppGlobalProvider] App Resumed -> Triggering Scan");
      scanSlips();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    super.dispose();
  }

  Future<void> _initAI() async {
    try {
      await _aiService.initialize();
      _isAIModelLoaded = true;
      notifyListeners();
      print("[AppGlobalProvider] AI Model Loaded.");
    } catch (e) {
      print("[AppGlobalProvider] AI Init Error: $e");
    }
  }

  // Original "Button" Logic moved here
  Future<int> scanSlips() async {
    if (_isScanning) return 0;
    _isScanning = true;
    notifyListeners();

    try {
      // 1. Check Folder Selection
      final selectedAlbumIds = await _historyService.getSelectedAlbumIds();
      
      // 2. Fetch Images
      List<File> newImages = [];
      
      // Reload IDs
      final albumIds = await _historyService.getSelectedAlbumIds();
      
      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      
      if (albumIds.isEmpty) {
        // Fallback: Scan "Recent"
        if (albums.isNotEmpty) {
           // Usually first one is Recent
           final recent = albums.first;
           await _scanAlbum(recent, newImages);
        }
      } else {
        for (final album in albums) {
          if (albumIds.contains(album.id)) {
            await _scanAlbum(album, newImages);
          }
        }
      }

      // Sort Oldest -> Newest
      newImages.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      if (newImages.isEmpty) {
        // print("[AppGlobalProvider] No new slips found."); // Reduce noise
        return 0;
      }

      print("[AppGlobalProvider] Found ${newImages.length} new images to process.");

      // 3. Insert Pending Messages (The "Reading..." cards)
      for (final file in newImages) {
        final msg = ChatMessage(
          text: "Slip: ${file.path.split('/').last}",
          isUser: false, // System message
          timestamp: DateTime.now(),
          imagePath: file.path,
          // slipData is null initially -> "Reading..."
        );
        await DatabaseService().addChatMessage(msg);
      }
      
      // 4. Process Background Queue
      _processSlipQueue(newImages);

      return newImages.length;

    } catch (e) {
      print("[AppGlobalProvider] Scan Error: $e");
      return 0;
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> _scanAlbum(AssetPathEntity album, List<File> newImages) async {
    final cutoffDate = await _historyService.getCutoffDate(album.id);
    final assetCount = await album.assetCountAsync;
    // Limit to 200 to avoid freezing
    final assets = await album.getAssetListRange(start: 0, end: assetCount > 200 ? 200 : assetCount);
    
    for (final asset in assets) {
      if (asset.type == AssetType.image && asset.createDateTime.isAfter(cutoffDate)) {
          final file = await asset.file;
          if (file != null) newImages.add(file);
      }
    }
    // Update history for this album
    await _historyService.updateLastScanTime(album.id);
  }

  Future<void> _processSlipQueue(List<File> files) async {
    for (final file in files) {
      ChatMessage? msg;
      try {
        final box = DatabaseService().chatBox;
        try {
          msg = box.values.firstWhere((m) => m.imagePath == file.path);
        } catch (_) {
          continue;
        }
        
        if (msg.isInBox) {
          final slip = await _scannerService.processImageFile(file);
          if (slip != null) {
            msg.slipData = {
              'bank': slip.bank,
              'amount': slip.amount,
              'date': slip.date,
              'memo': slip.memo,
              'recipient': slip.recipient,
              'category': 'Uncategorized', // Default
            };
            await msg.save(); 
          } else {
             msg.slipData = {'error': true};
             msg.text = "Failed to read slip.";
             await msg.save();
          }
        }
      } catch (e) {
        print("Error processing slip in provider: $e");
        if (msg != null && msg.isInBox) {
           msg.slipData = {'error': true};
           msg.text = "Error: $e";
           await msg.save();
        }
      }
    }
  }

  void clearPendingSlips() {
    _pendingSlips.clear();
    notifyListeners();
  }
}
