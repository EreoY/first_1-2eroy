import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction.dart';
import '../models/chat_message.dart';
import '../models/income_schedule.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Box<Transaction>? _transactionBox;
  Box<ChatMessage>? _chatBox;
  Box? _settingsBox;

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(TransactionAdapter());
    Hive.registerAdapter(ChatMessageAdapter());
    
    Hive.registerAdapter(IncomeScheduleAdapter());

    _transactionBox = await _openBoxWithRecovery<Transaction>('expenses');
    _chatBox = await _openBoxWithRecovery<ChatMessage>('chat_messages');
    _settingsBox = await _openBoxWithRecovery('settings');
    _incomeScheduleBox = await _openBoxWithRecovery<IncomeSchedule>('income_schedules');
  }

  Future<Box<T>> _openBoxWithRecovery<T>(String name) async {
    try {
      return await Hive.openBox<T>(name);
    } catch (e) {
      print("Error opening box '$name': $e. Deleting and recreating...");
      await Hive.deleteBoxFromDisk(name);
      return await Hive.openBox<T>(name);
    }
  }

  Box<IncomeSchedule>? _incomeScheduleBox;
  Box<IncomeSchedule> get incomeScheduleBox => _incomeScheduleBox!;

  Future<void> addTransaction(String item, double price, {String category = 'Uncategorized', double qty = 1.0, DateTime? date, String? note, String? slipImagePath, String type = 'expense', String? source, String? scannedBank}) async {
    final transaction = Transaction(
      item: item,
      price: price,
      date: date ?? DateTime.now(),
      category: category,
      qty: qty,
      note: note,
      slipImagePath: slipImagePath,
      type: type,
      source: source,
      scannedBank: scannedBank,
    );
    await _transactionBox!.add(transaction);
  }

  Future<void> addChatMessage(ChatMessage message) async {
    await _chatBox!.add(message);
  }

  List<Transaction> getAllTransactions() {
    return _transactionBox?.values.toList() ?? [];
  }
  
  List<ChatMessage> getChatHistory() {
    return _chatBox?.values.toList() ?? [];
  }
  
  Box<ChatMessage> get chatBox => _chatBox!;
  Box<Transaction> get transactionBox => _transactionBox!;
  Box get settingsBox => _settingsBox!;
}
