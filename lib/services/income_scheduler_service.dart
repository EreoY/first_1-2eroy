import 'package:uuid/uuid.dart';
import '../models/income_schedule.dart';
import '../models/chat_message.dart';
import 'database_service.dart';
import '../providers/app_global_provider.dart';

class IncomeSchedulerService {
  final DatabaseService _db = DatabaseService();

  // Singleton pattern
  static final IncomeSchedulerService _instance = IncomeSchedulerService._internal();
  factory IncomeSchedulerService() => _instance;
  IncomeSchedulerService._internal();

  List<IncomeSchedule> getFavorites() {
    final items = _db.incomeScheduleBox.values.where((s) => s.isFavorite).toList();
    items.sort((a, b) => a.order.compareTo(b.order));
    return items;
  }

  List<IncomeSchedule> getUpcomingItems() {
    final items = _db.incomeScheduleBox.values.toList();
    items.sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
    return items;
  }

  Future<void> addSchedule({
    required String title,
    required double amount,
    required String recurrenceRule, // 'monthly_1st', 'weekly_mon', 'manual'
    required DateTime nextDueDate,
    bool isFavorite = false,
  }) async {
    print("DEBUG: Service addSchedule called");
    // Determine new order (last + 1)
    int newOrder = 0;
    if (isFavorite) {
      final existing = getFavorites();
      if (existing.isNotEmpty) {
        newOrder = existing.last.order + 1;
      }
    }

    final schedule = IncomeSchedule(
      id: const Uuid().v4(),
      title: title,
      amount: amount,
      recurrenceRule: recurrenceRule,
      nextDueDate: nextDueDate,
      isFavorite: isFavorite,
      order: newOrder,
    );
    try {
      print("DEBUG: Adding to Hive box");
      await _db.incomeScheduleBox.add(schedule);
      print("DEBUG: Added to Hive box");
    } catch (e) {
      print("DEBUG: Error adding to Hive: $e");
      rethrow;
    }
  }

  Future<void> reorderFavorites(int oldIndex, int newIndex) async {
    final favorites = getFavorites();
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = favorites.removeAt(oldIndex);
    favorites.insert(newIndex, item);

    // Update order for all affected items
    for (int i = 0; i < favorites.length; i++) {
      favorites[i].order = i;
      await favorites[i].save();
    }
  }

  Future<void> checkDueItems(AppGlobalProvider provider) async {
    final now = DateTime.now();
    // Find items that are due
    final dueItems = _db.incomeScheduleBox.values.where((s) {
      return s.nextDueDate.isBefore(now) || s.nextDueDate.isAtSameMomentAs(now);
    }).toList();

    int newDueCount = 0;

    for (final item in dueItems) {
      // 1. Generate Reminder for THIS due date
      await _injectReminderMessage(item, item.nextDueDate);
      newDueCount++;

      // 2. Advance the schedule immediately
      if (item.recurrenceRule == 'manual') {
        // One-off item (e.g. snoozed), delete it
        await item.delete();
      } else {
        // Recurring item, calculate next date
        item.nextDueDate = _calculateNextDueDate(item.nextDueDate, item.recurrenceRule);
        // If the calculated next date is STILL in the past (e.g. user offline for months),
        // the loop in the NEXT checkDueItems call (or recursion) would handle it.
        // For safety/performance, we could loop here, but letting the timer handle it is safer to avoid blocking.
        await item.save();
      }
    }

    // Update provider count based on MESSAGES, not schedules anymore
    provider.updatePendingIncomeCount();
  }

  Future<void> _injectReminderMessage(IncomeSchedule item, DateTime dueDate) async {
    final msg = ChatMessage(
      text: "💰 ถึงกำหนดรับ: ${item.title}",
      isUser: false,
      timestamp: DateTime.now(),
      mode: 'income',
      expenseData: [
        {
          'type': 'reminder',
          'scheduleId': item.id,
          'title': item.title,
          'amount': item.amount,
          'dueDate': dueDate.toIso8601String(), // Store specific due date
        }
      ],
    );
    await _db.addChatMessage(msg);
  }

  Future<void> snoozeItem(String title, double amount, Duration delay) async {
    // Create a one-off schedule for the snooze
    final snoozeDate = DateTime.now().add(delay);
    
    final schedule = IncomeSchedule(
      id: const Uuid().v4(),
      title: title,
      amount: amount,
      recurrenceRule: 'manual', // One-off
      nextDueDate: snoozeDate,
      isFavorite: false,
    );
    await _db.incomeScheduleBox.add(schedule);
  }

  Future<void> confirmItem(String scheduleId, {String? title, double? amount}) async {
    // Try to find the schedule
    IncomeSchedule? item;
    try {
      item = _db.incomeScheduleBox.values.firstWhere((s) => s.id == scheduleId);
    } catch (_) {
      // Not found (e.g. one-off schedule that was auto-deleted)
      item = null;
    }
    
    // 1. Create Transaction
    // Use item data if available, otherwise use passed data (from ChatMessage)
    final finalTitle = item?.title ?? title ?? "Unknown Income";
    final finalAmount = item?.amount ?? amount ?? 0.0;

    await _db.addTransaction(
      finalTitle,
      finalAmount,
      category: 'Salary', // Or make this dynamic if needed
      qty: 1.0,
      date: DateTime.now(),
      type: 'income',
    );

    // 2. Calculate Next Due Date (Only if schedule exists and is recurring)
    // If it was auto-advanced already (in checkDueItems), we don't need to do anything here.
    // If it was a one-off that was deleted, we also don't need to do anything.
    // The only case we might need to update is if we DIDN'T auto-advance in checkDueItems,
    // but we changed that logic to ALWAYS auto-advance.
    // So actually, we don't need to update the schedule here anymore!
    // checkDueItems handles the advancement.
  }

  DateTime _calculateNextDueDate(DateTime currentDue, String rule) {
    if (rule == 'daily') {
      return currentDue.add(const Duration(days: 1));
    } else if (rule == 'weekly') {
      return currentDue.add(const Duration(days: 7));
    } else if (rule == 'monthly') {
      // Same day next month
      // Handle edge cases (e.g., Jan 31 -> Feb 28/29)
      int newMonth = currentDue.month + 1;
      int newYear = currentDue.year;
      if (newMonth > 12) {
        newMonth = 1;
        newYear++;
      }
      
      int newDay = currentDue.day;
      // Clamp day to max days in new month
      final daysInNewMonth = DateTime(newYear, newMonth + 1, 0).day;
      if (newDay > daysInNewMonth) {
        newDay = daysInNewMonth;
      }
      
      return DateTime(newYear, newMonth, newDay, currentDue.hour, currentDue.minute);
    } else if (rule.startsWith('custom_days_')) {
      final days = int.tryParse(rule.split('_').last) ?? 1;
      return currentDue.add(Duration(days: days));
    } else if (rule == 'monthly_1st') {
      // Legacy support
      return DateTime(currentDue.year, currentDue.month + 1, 1, currentDue.hour, currentDue.minute);
    } else if (rule == 'monthly_25th') {
      // Legacy support
      return DateTime(currentDue.year, currentDue.month + 1, 25, currentDue.hour, currentDue.minute);
    }
    
    // Default fallback
    return currentDue.add(const Duration(days: 30));
  }
}
