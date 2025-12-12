import 'package:flutter/material.dart';
import '../../models/chat_message.dart';
import '../../services/income_scheduler_service.dart';
import 'package:intl/intl.dart';

class ReminderCard extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback onActionCompleted;

  const ReminderCard({
    super.key,
    required this.message,
    required this.onActionCompleted,
  });

  @override
  State<ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<ReminderCard> {
  bool _isProcessing = false;
  final IncomeSchedulerService _service = IncomeSchedulerService();

  Future<void> _confirm() async {
    setState(() => _isProcessing = true);
    try {
      final data = widget.message.expenseData![0];
      final scheduleId = data['scheduleId'];
      final title = data['title'];
      final amount = data['amount'];

      await _service.confirmItem(scheduleId, title: title, amount: amount);
      
      // Mark message as saved/processed
      widget.message.isSaved = true;
      await widget.message.save();
      
      widget.onActionCompleted();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _snooze() async {
    // Show dialog to pick duration
    int? durationValue;
    String durationUnit = 'days'; // 'minutes', 'hours', 'days'

    final result = await showDialog<Duration>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Snooze Duration"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Duration"),
                  onChanged: (v) => durationValue = int.tryParse(v),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text("Minutes"),
                      selected: durationUnit == 'minutes',
                      onSelected: (b) => setState(() => durationUnit = 'minutes'),
                    ),
                    ChoiceChip(
                      label: const Text("Hours"),
                      selected: durationUnit == 'hours',
                      onSelected: (b) => setState(() => durationUnit = 'hours'),
                    ),
                    ChoiceChip(
                      label: const Text("Days"),
                      selected: durationUnit == 'days',
                      onSelected: (b) => setState(() => durationUnit = 'days'),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  if (durationValue != null && durationValue! > 0) {
                    Duration d;
                    if (durationUnit == 'minutes') {
                      d = Duration(minutes: durationValue!);
                    } else if (durationUnit == 'hours') {
                      d = Duration(hours: durationValue!);
                    } else {
                      d = Duration(days: durationValue!);
                    }
                    Navigator.pop(context, d);
                  }
                },
                child: const Text("Snooze"),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      setState(() => _isProcessing = true);
      try {
        final data = widget.message.expenseData![0];
        
        // Create One-off Schedule
        await _service.snoozeItem(data['title'], data['amount'], result);
        
        // Delete this reminder card (since we snoozed it, it will come back later as a new card)
        await widget.message.delete();
        
        widget.onActionCompleted();
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _skip() async {
    setState(() => _isProcessing = true);
    try {
      // Just mark as saved/handled without creating transaction
      widget.message.text = "${widget.message.text} (Skipped)";
      widget.message.isSaved = true;
      await widget.message.save();
      
      widget.onActionCompleted();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.message.expenseData![0];
    final title = data['title'];
    final amount = data['amount'];
    final dueDateStr = data['dueDate'];
    DateTime? dueDate;
    if (dueDateStr != null) {
      dueDate = DateTime.parse(dueDateStr);
    }
    
    final isHandled = widget.message.isSaved;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: isHandled 
            ? Colors.grey.withOpacity(0.1) 
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: isHandled 
            ? Border.all(color: Colors.transparent)
            : Border.all(color: Colors.orange.withOpacity(0.5), width: 1.5),
        boxShadow: isHandled ? [] : [
          BoxShadow(color: Colors.orange.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title (No Icon here anymore)
                Padding(
                  padding: const EdgeInsets.only(right: 24.0), // Space for the icon
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isHandled ? Colors.grey : null,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (dueDate != null)
                  Text(
                    "สำหรับวันที่: ${DateFormat('d MMM yyyy').format(dueDate)}",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                const SizedBox(height: 4),
                Text(
                  NumberFormat('#,##0.00').format(amount),
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                if (isHandled)
                  const Text("✅ Handled", style: TextStyle(color: Colors.green))
                else if (_isProcessing)
                  const Center(child: CircularProgressIndicator())
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _skip,
                        style: TextButton.styleFrom(foregroundColor: Colors.grey),
                        child: const Text("ยกเลิก"),
                      ),
                      TextButton(
                        onPressed: _snooze,
                        child: const Text("เลื่อน"),
                      ),
                      ElevatedButton(
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("รับแล้ว"),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Positioned Icon
          if (!isHandled)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active, 
                  color: Colors.orange, 
                  size: 16
                ),
              ),
            ),
        ],
      ),
    );
  }
}
