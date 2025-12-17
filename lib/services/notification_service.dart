import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart'; // Add crypto package
import '../models/chat_message.dart';
import 'database_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const MethodChannel _channel = MethodChannel('com.example.expense/notification');
  
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isListening = false;
  bool get isListening => _isListening;

  // Whitelisted packages
  static const List<String> _whitelistPackages = [
    'com.kasikorn.retail.mbanking', // KPlus
    'com.scb.phone', // SCB Easy
    'com.ktb.ktbnetbank', // Krungthai Next
    'ktbcs.netbank', // Krungthai Next (New)
    'com.bbl.mobilebanking', // Bangkok Bank
    'com.krungsri.kma', // KMA
    'com.tmbtouch.uk.mbanking', // TTB Touch
    'com.gsb.mymo', // GSB MyMo
    'th.co.truemoney.wallet', // TrueMoney
  ];

  Future<void> init() async {
    // Init Local Notifications for feedback
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    // Set Method Call Handler
    _channel.setMethodCallHandler(_handleMethodCall);
    
    // Load persisted state
    final prefs = await SharedPreferences.getInstance();
    _isListening = prefs.getBool('auto_track_enabled') ?? false;

    // Retroactive Sync: Check for active notifications on start
    if (_isListening) {
      await checkActiveNotifications();
    }
  }

  Future<void> checkActiveNotifications() async {
    if (!Platform.isAndroid) return;
    try {
      print("[NotificationService] Checking active notifications...");
      await _channel.invokeMethod('checkActiveNotifications');
    } catch (e) {
      print("Error checking active notifications: $e");
    }
  }

  Future<void> startListening() async {
    if (!Platform.isAndroid) return;
    print("[NotificationService] Starting listening...");
    _isListening = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_track_enabled', true);
    
    // Check for missed notifications immediately
    await checkActiveNotifications();
  }

  Future<void> stopListening() async {
    if (!Platform.isAndroid) return;
    print("[NotificationService] Stopping listening...");
    _isListening = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_track_enabled', false);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == "onNotification") {
      final data = Map<String, dynamic>.from(call.arguments);
      print('[DART_NOTIF] Received from Native: ${data['title']} - ${data['text']}'); // SPY LOG

      if (!_isListening) return;
      try {
        await _processNotification(data);
      } catch (e) {
        print("Error processing notification: $e");
      }
    }
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod('openNotificationSettings');
      return true;
    } catch (e) {
      print("Error requesting permission: $e");
      return false;
    }
  }

  Future<bool> checkPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? granted = await _channel.invokeMethod('isPermissionGranted');
      return granted ?? false;
    } catch (e) {
      print("Error checking permission: $e");
      return false;
    }
  }

  String _generateFingerprint(String packageName, String title, String text, int postTime) {
    final raw = "$packageName|$title|$text|$postTime";
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _processNotification(Map<String, dynamic> data) async {
    final String? packageName = data['packageName'];
    final String? title = data['title'];
    final String? text = data['text'];
    final int postTime = data['postTime'] ?? 0; // Default to 0 if missing (shouldn't happen with new native code)

    print("[NotificationService] Received: $packageName | Title: $title | Text: $text");

    if (packageName == null || !_whitelistPackages.contains(packageName)) {
      return;
    }

    // Deduplication Logic
    final fingerprint = _generateFingerprint(packageName, title ?? "", text ?? "", postTime);
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('processed_notification_ids') ?? [];

    if (history.contains(fingerprint)) {
      print("[NotificationService] Duplicate ignored (Fingerprint: $fingerprint)");
      return;
    }

    try {
      // Parse
      final result = _parseNotification(packageName, title ?? "", text ?? "");
      
      if (result != null) {
        // Construct the exact JSON format user requested for debugging
        final debugJson = jsonEncode([{'amount': result['amount']}]);
        print("[AI_DEBUG] Raw Response: $debugJson");
        print("[NotificationService] Parsed Result: $result");
        
        // Save Fingerprint to History
        history.add(fingerprint);
        // Keep history size manageable (e.g., last 100)
        if (history.length > 100) {
          history.removeAt(0);
        }
        await prefs.setStringList('processed_notification_ids', history);

        final DateTime currentTimestamp = DateTime.now();

        // Check Auto-Save Preference
        final isAutoSaveIncome = prefs.getBool('auto_save_income') ?? false;

        // 1. Add Conversational Message
        final botMsg = ChatMessage(
          text: isAutoSaveIncome 
              ? "บันทึกรายรับอัตโนมัติ: ${result['amount']} บาท จาก ${result['source']} ✅"
              : "มีเงินเข้า ${result['amount']} บาท จาก ${result['source']} ครับ 💸",
          isUser: false,
          timestamp: currentTimestamp,
          mode: 'income',
          isSaved: true,
        );
        await DatabaseService().addChatMessage(botMsg);

        // 2. Perform Auto-Save if enabled
        if (isAutoSaveIncome) {
           print("[NotificationService] Auto-saving income transaction...");
           await DatabaseService().addTransaction(
              result['source'], // Title
              (result['amount'] as num).toDouble(),
              category: 'Salary', // Default
              qty: 1.0,
              date: currentTimestamp,
              type: 'income',
           );
        }

        // 3. Add the Proposal Card (Actionable Item)
        final chatMsg = ChatMessage(
          text: "Income Proposal", // Hidden text for card
          isUser: false,
          timestamp: currentTimestamp.add(const Duration(milliseconds: 100)),
          mode: 'income',
          isSaved: isAutoSaveIncome, // Mark as saved if auto-saved
          expenseData: [
            {
              'item': result['item'],
              'amount': result['amount'],
              'price': result['amount'],
              'type': 'income',
              'source': result['source'],
              'category': 'Income',
              'qty': 1.0,
              'date': currentTimestamp.toIso8601String(),
            }
          ],
        );
        
        await DatabaseService().addChatMessage(chatMsg);

        // Show Feedback Notification
        _showFeedbackNotification(result['amount'], result['source'], isPending: !isAutoSaveIncome);
      }
    } catch (e) {
      print("Error in notification handler: $e");
    }
  }

  Map<String, dynamic>? _parseNotification(String packageName, String title, String text) {
    String content = "$title $text";
    double? amount;
    String source = 'Unknown';

    // 1. STRICT FILTER: Must be Income
    // Keywords: เงินเข้า, รับเงิน, received, deposit, money in, cash in, transfer in, topup, เติมเงิน
    final incomeRegex = RegExp(r'(เงินเข้า|รับเงิน|received|deposit|money in|cash in|transfer in|topup|เติมเงิน|เงินโอนเข้า)', caseSensitive: false);
    // Exclude: paid, expense, sent, transfer to, ชำระ, โอนออก, หักบัญชี
    final expenseRegex = RegExp(r'(paid|expense|sent|transfer to|ชำระ|โอนออก|โอนให้|หักบัญชี)', caseSensitive: false);

    if (!incomeRegex.hasMatch(content)) {
      return null;
    }

    if (expenseRegex.hasMatch(content)) {
      return null;
    }

    // 2. Extract Amount & Source
    if (packageName.contains('kasikorn')) { // KPlus
      source = 'KPlus';
      // "เงินเข้า 500.00 บาท", "received 500.00 Baht"
      final regex = RegExp(r'(?:เงินเข้า|received)\s+([0-9,.]+)\s+(?:บาท|Baht)', caseSensitive: false);
      final match = regex.firstMatch(content);
      if (match != null) amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
    } 
    else if (packageName.contains('scb')) { // SCB
      source = 'SCB';
      // "เงินเข้า 1,200.00 บ.", "เงินเข้า 1,200.00 บาท"
      final regex = RegExp(r'เงินเข้า\s+([0-9,.]+)\s+(?:บ\.|บาท)', caseSensitive: false);
      final match = regex.firstMatch(content);
      if (match != null) amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
    }
    else if (packageName.contains('ktb') || packageName.contains('ktbcs')) { // Krungthai
      source = 'Krungthai';
      // "เงินเข้า 350.00 บ.", "Deposit 350.00 Baht", "ได้รับ +10.00 บาท"
      final regex = RegExp(r'(?:เงินเข้า|Deposit|ได้รับ|โอนเข้า)\s+(?:\+)?([0-9,.]+)\s+(?:บ\.|Baht|บาท)', caseSensitive: false);
      final match = regex.firstMatch(content);
      if (match != null) amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
    }
    else if (packageName.contains('bbl')) { // Bangkok Bank
      source = 'Bangkok Bank';
      // "เงินโอนเข้า 2,000.00 บาท", "Cash in 2,000.00 Baht"
      final regex = RegExp(r'(?:เงินโอนเข้า|Cash in|Transfer in)\s+([0-9,.]+)\s+(?:บาท|Baht)', caseSensitive: false);
      final match = regex.firstMatch(content);
      if (match != null) amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
    }
    else if (packageName.contains('krungsri')) { // KMA
      source = 'KMA';
      // "เงินเข้าบัญชี xxx จำนวน 150.00 บาท"
      final regex = RegExp(r'เงินเข้าบัญชี.*?จำนวน\s+([0-9,.]+)\s+บาท', caseSensitive: false);
      final match = regex.firstMatch(content);
      if (match != null) amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
    }
    else if (packageName.contains('tmbtouch')) { // TTB
      source = 'TTB';
      // "มีเงินเข้า 5,000.00 บาท"
      final regex = RegExp(r'มีเงินเข้า\s+([0-9,.]+)\s+บาท', caseSensitive: false);
      final match = regex.firstMatch(content);
      if (match != null) amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
    }
    else if (packageName.contains('gsb')) { // GSB
      source = 'GSB';
      // "เงินเข้า 400.00 บาท"
      final regex = RegExp(r'เงินเข้า\s+([0-9,.]+)\s+บาท', caseSensitive: false);
      final match = regex.firstMatch(content);
      if (match != null) amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
    }
    else if (packageName.contains('truemoney')) { // TrueMoney
      source = 'TrueMoney';
      // "เติมเงิน 100.00 บาท", "รับเงิน 100.00 บาท", "Topup 100.00 Baht"
      final regex = RegExp(r'(?:เติมเงิน|รับเงิน|Topup)\s+([0-9,.]+)\s+(?:บาท|Baht|สำเร็จ|จาก)', caseSensitive: false);
      final match = regex.firstMatch(content);
      if (match != null) amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
    }
    else {
      // Fallback (still strict income)
      source = packageName;
      final amountRegex = RegExp(r'[\d,]+\.\d{2}'); 
      final match = amountRegex.firstMatch(content);
      if (match != null) {
        String rawAmount = match.group(0)!.replaceAll(',', '');
        amount = double.tryParse(rawAmount);
      }
    }

    if (amount == null) return null;

    return {
      'item': 'Income Proposal',
      'amount': amount,
      'type': 'income', // Strictly Income
      'source': source,
    };
  }

  Future<void> _showFeedbackNotification(double amount, String source, {bool isPending = false}) async {
    const androidDetails = AndroidNotificationDetails(
      'eroy_channel',
      'Eroy Notifications',
      channelDescription: 'Notifications for auto-tracked transactions',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    
    final title = isPending ? 'New Income Detected' : 'Recorded Transaction';
    final body = isPending 
        ? '💰 $amount from $source. Tap to review.' 
        : 'Saved $amount from $source';

    await _localNotifications.show(
      DateTime.now().millisecond, // ID
      title,
      body,
      details,
    );
  }
}
