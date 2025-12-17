import '../models/chat_message.dart';
import '../services/database_service.dart';
import '../services/category_classifier_service.dart';
import 'category_styles.dart';

class TransactionHelper {
  static Future<void> saveSlipAsTransaction(ChatMessage message, Map<String, dynamic> slipData) async {
    if (message.isSaved) return;

    // 1. Robust Fallback for Category - รองรับภาษาไทยจาก LLM
    String category = slipData['category'] ?? 'Uncategorized';
    
    // แปลงจากภาษาไทยเป็นอังกฤษถ้าจำเป็น (Check if contains Thai characters)
    if (category.contains(RegExp(r'[\u0E00-\u0E7F]'))) {
      category = CategoryStyles.thaiToEnglish(category);
      slipData['category'] = category; // อัพเดทให้เป็นภาษาอังกฤษ
      print("[TransactionHelper] แปลง category: ${slipData['category']} → $category");
    }
    
    if (category == 'Uncategorized' || category == null || category == 'Other') {
       // Fallback: ลองใช้ rule-based อีกครั้ง
       String contextText = "${slipData['bank']} ${slipData['recipient']} ${slipData['memo']}";
       category = CategoryClassifierService().suggestCategory(contextText);
       slipData['category'] = category;
       print("[TransactionHelper] Fallback: ใช้ rule-based category: $category");
    }

    // 2. Robust Fallback for Memo (Item Name)
    String itemName = slipData['memo'] ?? '';
    if (itemName.isEmpty) {
      itemName = slipData['recipient'] ?? 'Unspecified Expense';
      slipData['memo'] = itemName; // Update the map
    }

    // 3. Determine Source and Scanned Bank
    String scannedBank = slipData['bank'] ?? 'Unknown Slip';
    String source = scannedBank;
    
    // If unknown, default source to 'Cash' (as per user request)
    if (scannedBank == 'Unknown Slip') {
      source = 'Cash';
    }

    await DatabaseService().addTransaction(
      itemName,
      (slipData['amount'] ?? 0.0).toDouble(),
      category: category,
      date: slipData['date'] is DateTime ? slipData['date'] : DateTime.now(),
      note: slipData['memo'], // Use memo for note, bank is now in source/scannedBank
      slipImagePath: message.imagePath,
      type: 'expense', // Slips are expenses for now
      source: source,
      scannedBank: scannedBank,
    );
    
    // Ensure message object is updated before saving
    message.slipData = slipData;
    message.isSaved = true;
    await message.save();
  }
}
