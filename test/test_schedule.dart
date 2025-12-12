import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:offline_ai_expense_tracker/models/income_schedule.dart';
import 'package:offline_ai_expense_tracker/services/database_service.dart';
import 'package:offline_ai_expense_tracker/services/income_scheduler_service.dart';

void main() async {
  // Initialize Hive
  await Hive.initFlutter();
  
  // Register Adapters
  Hive.registerAdapter(IncomeScheduleAdapter());
  
  // Open Box
  await Hive.openBox<IncomeSchedule>('income_schedules');
  
  final service = IncomeSchedulerService();
  
  print("Adding schedule...");
  try {
    await service.addSchedule(
      title: "Test Salary",
      amount: 50000,
      recurrenceRule: "monthly",
      nextDueDate: DateTime.now(),
      isFavorite: false,
    );
    print("Schedule added successfully!");
    
    final items = service.getUpcomingItems();
    print("Items count: ${items.length}");
    for (var item in items) {
      print("Item: ${item.title}, ${item.amount}, ${item.recurrenceRule}");
    }
    
  } catch (e) {
    print("Error: $e");
  }
}
