import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPrefs
import '../services/ai_service.dart';
import '../services/slip_scanner_service.dart';
import '../services/scan_history_service.dart';
import '../services/database_service.dart';
import '../models/chat_message.dart';

import '../services/income_scheduler_service.dart';
import '../services/receipt_processor.dart';
import '../core/constants.dart'; // For ChatMode and Prompts
import '../utils/transaction_helper.dart'; // Import TransactionHelper
import 'dart:async'; // Add async import for Timer

class AppGlobalProvider extends ChangeNotifier with WidgetsBindingObserver {
  final AIService _aiService = AIService();
  final SlipScannerService _scannerService = SlipScannerService();
  final ScanHistoryService _historyService = ScanHistoryService();
  final IncomeSchedulerService _schedulerService = IncomeSchedulerService();

  bool _isAIModelLoaded = false;
  bool get isAIModelLoaded => _isAIModelLoaded;

  List<SlipData> _pendingSlips = [];
  List<SlipData> get pendingSlips => _pendingSlips;
  
  int _pendingIncomeCount = 0;
  int get pendingCount => _pendingSlips.length + _pendingIncomeCount;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  Timer? _scanTimer;

  Future<void> initialize() async {
    print("[AppGlobalProvider] Initializing...");
    
    // 0. Register Lifecycle Observer
    WidgetsBinding.instance.addObserver(this);

    // Load Settings
    await _loadSettings();
    
    // 1. Initialize AI (Background)
    _initAI();

    // 2. Auto-Scan Slips (Using "Button" Logic)
    Future.delayed(const Duration(seconds: 1), () {
      _resumeStuckSlips(); // Resume processing stuck slips
      scanSlips(); 
      checkDueIncome();
    });

    // 3. Periodic Scan (Every 60 Seconds)
    _scanTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      // print("[AppGlobalProvider] Periodic Scan Triggered"); // Reduced noise
      scanSlips();
      checkDueIncome(); 
    });
  }

  Future<void> _resumeStuckSlips() async {
    print("[AppGlobalProvider] Checking for stuck slips...");
    final box = DatabaseService().chatBox;
    // Find messages that have image but no slipData (stuck in "Reading...")
    final stuckMessages = box.values.where((m) => m.imagePath != null && m.slipData == null).toList();
    
    if (stuckMessages.isNotEmpty) {
      print("[AppGlobalProvider] Found ${stuckMessages.length} stuck slips. Resuming...");
      final files = stuckMessages.map((m) => File(m.imagePath!)).toList();
      _processSlipQueue(files);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("[AppGlobalProvider] App Resumed -> Triggering Scan");
      scanSlips();
      checkDueIncome();
    }
  }

  Future<void> checkDueIncome() async {
    await _schedulerService.checkDueItems(this);
  }

  void updatePendingIncomeCount() {
    // Count pending reminder messages in ChatBox
    final pendingReminders = DatabaseService().chatBox.values.where((msg) {
      if (msg.mode != 'income' || msg.isSaved) return false;
      if (msg.expenseData == null || msg.expenseData!.isEmpty) return false;
      return msg.expenseData![0]['type'] == 'reminder';
    }).length;
    
    _pendingIncomeCount = pendingReminders;
    notifyListeners();
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
      print("[AppGlobalProvider] AI Model Loaded.");
    } catch (e) {
      print("[AppGlobalProvider] AI Init Error: $e");
      // Proceed anyway so the app doesn't get stuck
    } finally {
      _isAIModelLoaded = true;
      notifyListeners();
    }
  }

  // Refactored to use SlipScannerService (Single Source of Truth)
  Future<int> scanSlips({bool isManual = false}) async {
    if (_isScanning) return 0;
    _isScanning = true;
    notifyListeners();

    try {
      // 0. Check if folders are selected (User Requirement: Must select first)
      final selectedAlbumIds = await _historyService.getSelectedAlbumIds();
      
      if (!isManual && selectedAlbumIds.isEmpty) {
        print("[AppGlobalProvider] Auto-Scan Aborted: No folders selected.");
        return 0;
      }

      // Delegate to SlipScannerService to just FETCH files (Smart Fetch)
      final newFiles = await _scannerService.fetchNewSlipFiles(isManual: isManual);

      if (newFiles.isEmpty) {
        return 0;
      }

      print("[AppGlobalProvider] Found ${newFiles.length} new images. Creating UI cards...");

      // 1. Create "Reading..." Cards IMMEDIATELY
      for (final file in newFiles) {
        final msg = ChatMessage(
          text: "Slip: ${file.path.split('/').last}",
          isUser: false, // System message
          timestamp: DateTime.now(),
          imagePath: file.path,
          // slipData is null -> UI shows "Reading..."
        );
        await DatabaseService().addChatMessage(msg);
      }

      // 2. Process in Background (Update Cards)
      _processSlipQueue(newFiles);

      return newFiles.length;

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

  bool _isAutoSaveSlips = false;
  bool get isAutoSaveSlips => _isAutoSaveSlips;
  
  bool _isAutoSaveIncome = false;
  bool get isAutoSaveIncome => _isAutoSaveIncome;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isAutoSaveSlips = prefs.getBool('auto_save_slips') ?? false;
    _isAutoSaveIncome = prefs.getBool('auto_save_income') ?? false;
    notifyListeners();
  }

  Future<void> toggleAutoSaveSlips(bool value) async {
    _isAutoSaveSlips = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_save_slips', _isAutoSaveSlips);
    notifyListeners();
  }

  Future<void> toggleAutoSaveIncome(bool value) async {
    _isAutoSaveIncome = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_save_income', _isAutoSaveIncome);
    notifyListeners();
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
            final slipDataMap = {
              'bank': slip.bank,
              'amount': slip.amount,
              'date': slip.date,
              'memo': slip.memo,
              'recipient': slip.recipient,
              'category': slip.category,
            };
            
            msg.slipData = slipDataMap;
            await msg.save(); 

            // Auto Save Logic (Slips)
            if (_isAutoSaveSlips) {
              print("[AppGlobalProvider] Auto-saving slip: ${file.path}");
              await TransactionHelper.saveSlipAsTransaction(msg, slipDataMap);
            }
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
  // Centralized Message Processing (Survives Screen Transitions)
  Future<void> processUserMessage(String text, ChatMode mode) async {
    // 1. Add User Message
    final userMsg = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      mode: mode.name,
    );
    await DatabaseService().addChatMessage(userMsg);

    // 2. Select Prompt based on Mode
    final String promptTemplate = mode == ChatMode.expense 
        ? AppConstants.kExpenseSystemPrompt 
        : AppConstants.kIncomeSystemPrompt;

    try {
      // 3. Process with AI
      final processor = ReceiptProcessor(_aiService);
      final results = await processor.processInputSteps(text, promptTemplate: promptTemplate);

      // 4. Add AI Response Message
      String responseText;
      List<Map<String, dynamic>>? expenseData;
      
      if (mode == ChatMode.expense) {
        if (results.isNotEmpty) {
           responseText = "เจอ ${results.length} รายการครับ ตรวจสอบความถูกต้องแล้วกดบันทึกได้เลย";
           expenseData = results;
        } else {
           responseText = "ไม่พบรายการค่าใช้จ่ายในข้อความครับ";
        }
      } else {
        // Income Mode
        if (results.isNotEmpty) {
           responseText = "เจอรายการรับครับ ตรวจสอบแล้วบันทึกได้เลย";
           expenseData = results; 
        } else {
           responseText = "ไม่พบยอดเงินในข้อความครับ";
        }
      }

      final aiMsg = ChatMessage(
        text: responseText,
        isUser: false,
        timestamp: DateTime.now(),
        expenseData: expenseData,
        mode: mode.name,
      );
      await DatabaseService().addChatMessage(aiMsg);
      print("[AppGlobalProvider] Debug: mode=$mode, expenseData=$expenseData");
      
      // Auto-Save Logic: REMOVED for manual chat as per user request.
      // "If we type chat ourselves... we must press save ourselves"

    } catch (e) {
      // Error Message
      final errorMsg = ChatMessage(
        text: "เกิดข้อผิดพลาด: $e",
        isUser: false,
        timestamp: DateTime.now(),
        mode: mode.name,
      );
      await DatabaseService().addChatMessage(errorMsg);
    }
  }
}
