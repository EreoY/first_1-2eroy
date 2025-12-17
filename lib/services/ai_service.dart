import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import 'llm_isolate_service.dart';

class AIService {
  // Singleton Pattern
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final LLMIsolateService _isolateService = LLMIsolateService();

  bool _isInitialized = false;
  int _emptyResponseCount = 0; // Watchdog counter
  static const int _maxEmptyResponses = 3; // Trigger reload after 3 empty responses

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    final modelPath = await _getModelPath();
    await _isolateService.initialize(modelPath);
    _isInitialized = true;
    print("[AIService] Initialized successfully.");
  }

  /// Force reload the model (for recovery)
  Future<void> _reloadModel() async {
    print("[AIService] 🔄 Force reloading model...");
    _isInitialized = false;
    await _isolateService.dispose();
    await initialize();
    _emptyResponseCount = 0; // Reset counter
    print("[AIService] ✅ Model reloaded successfully.");
  }

  Stream<String> processStep(String input, String promptTemplate) {
    // Replace {input} in prompt
    final fullPrompt = promptTemplate.replaceFirst("{input}", input);

    // 🔥 [DEBUG] LOG THE EXACT PROMPT
    print("--------------------------------------------------");
    print("[CHECK PROMPT] ACTUAL PROMPT SENT TO AI:");
    print(fullPrompt); 
    print("--------------------------------------------------");
    
    return _isolateService.generateStream(fullPrompt);
  }

  Future<String> predictCategory(String shopName) async {
    if (!_isInitialized) await initialize(); // Ensure init

    // Build Prompt
    final fullPrompt = AppConstants.kCategorizeSystemPrompt.replaceFirst("{input}", shopName);
    
    // 🔥 [DEBUG] Log Prompt
    print("[AIService] 🚀 Sending Prompt to Model:\n$fullPrompt\n-------------------------");

    try {
      // 🔥 CRITICAL: Reset context before each generation
      await _isolateService.resetContext();

      // ✅ FIXED: Consume stream ONCE and accumulate in buffer
      final buffer = StringBuffer();
      await for (final chunk in _isolateService.generateStream(fullPrompt)) {
        buffer.write(chunk);
      }
      
      final fullResponse = buffer.toString();
      
      // 🔥 [DEBUG] Log Raw Response
      print("[AIService] 📥 Raw Model Response: '$fullResponse'");

      if (fullResponse.trim().isEmpty) {
        print("[AIService] ❌ Error: Model returned empty response.");
        _emptyResponseCount++;
        
        // Watchdog: Auto-reload if too many failures
        if (_emptyResponseCount >= _maxEmptyResponses) {
          print("[AIService] ⚠️ Too many empty responses. Triggering model reload...");
          await _reloadModel();
          
          // Retry once after reload
          await _isolateService.resetContext();
          final retryBuffer = StringBuffer();
          await for (final chunk in _isolateService.generateStream(fullPrompt)) {
            retryBuffer.write(chunk);
          }
          
          final retryResponse = retryBuffer.toString();
          if (retryResponse.trim().isEmpty) {
            print("[AIService] ❌ Still empty after reload. Giving up.");
            return "อื่นๆ";
          }
          
          // Use retry response for parsing
          return _parseCategory(retryResponse);
        } else {
          return "อื่นๆ";
        }
      } else {
        // Reset counter on success
        _emptyResponseCount = 0;
      }
      
      return _parseCategory(fullResponse);
      
    } catch (e) {
      print("[AIService] ❌ Categorization Exception: $e");
      return "อื่นๆ";
    }
  }

  /// Helper method to parse category from LLM response
  /// Simple format: {"category": "หมวดหมู่"}
  String _parseCategory(String fullResponse) {
    try {
      // Remove markdown code blocks if any
      String cleanText = fullResponse.replaceAll('```json', '').replaceAll('```', '').trim();
      
      // Extract JSON part
      int start = cleanText.indexOf('{');
      int end = cleanText.lastIndexOf('}');
      if (start != -1 && end != -1) {
        String jsonStr = cleanText.substring(start, end + 1);
        
        // Extract "category" field only
        final categoryRegex = RegExp(r'"category"\s*:\s*"([^"]+)"');
        final categoryMatch = categoryRegex.firstMatch(jsonStr);
        
        if (categoryMatch != null) {
          final category = categoryMatch.group(1);
          if (category != null && category.isNotEmpty) {
            print("[AIService] ✅ Category: $category");
            return category;
          }
        }
      }
      
      print("[AIService] ⚠️ Warning: JSON parsing failed or no category found.");
      
    } catch (e) {
      print("[AIService] ⚠️ Parse error: $e");
    }
    
    return "อื่นๆ"; // Fallback
  }

  Future<String> _getModelPath() async {
    // Unified logic for ALL platforms (Mobile & Linux)
    final directory = await getApplicationDocumentsDirectory();
    final modelPath = '${directory.path}/model-unsloth21.Q4_0.gguf';
    
    final file = File(modelPath);
    
    // Only copy if file doesn't exist
    if (!await file.exists()) {
      print("[AI_DEBUG] Copying fresh model from assets...");
      try {
        final byteData = await rootBundle.load('assets/models/model-unsloth21.Q4_0.gguf');
        await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
        print("[AI_DEBUG] Model copied successfully to $modelPath");
      } catch (e) {
        print("[AI_DEBUG] Error copying model: $e");
        throw e;
      }
    } else {
      print("[AI_DEBUG] Model found at $modelPath");
    }
    return modelPath;
  }
}
