import 'package:flutter/material.dart';
import '../../services/income_scheduler_service.dart';
import '../../models/income_schedule.dart';
import 'package:intl/intl.dart';

class UpcomingListModal extends StatefulWidget {
  const UpcomingListModal({super.key});

  @override
  State<UpcomingListModal> createState() => _UpcomingListModalState();
}

class _UpcomingListModalState extends State<UpcomingListModal> {
  final IncomeSchedulerService _service = IncomeSchedulerService();
  List<IncomeSchedule> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  void _loadItems() {
    setState(() {
      // Filter out "manual" templates (far future dates)
      _items = _service.getUpcomingItems().where((s) => s.recurrenceRule != 'manual').toList();
    });
  }

  void _showAddScheduleDialog({IncomeSchedule? itemToEdit}) {
    final titleController = TextEditingController(text: itemToEdit?.title ?? "");
    final amountController = TextEditingController(text: itemToEdit?.amount.toString() ?? "");
    
    String recurrence = itemToEdit?.recurrenceRule ?? 'monthly';
    // Handle custom rule parsing
    String customDays = "3";
    if (recurrence.startsWith('custom_days_')) {
      customDays = recurrence.split('_').last;
      recurrence = 'custom';
    }

    final customDaysController = TextEditingController(text: customDays);
    
    DateTime selectedDate = itemToEdit?.nextDueDate ?? DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(itemToEdit == null ? "Add Recurring Income" : "Edit Schedule"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: "Title (e.g. Salary)"),
                ),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: "Amount"),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                
                // Date & Time Picker Row
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                          );
                          if (date != null) {
                            setState(() => selectedDate = date);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: "Start Date"),
                          child: Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (time != null) {
                            setState(() => selectedTime = time);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: "Time"),
                          child: Text(selectedTime.format(context)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: recurrence,
                  decoration: const InputDecoration(labelText: "Recurrence"),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text("Every Day")),
                    DropdownMenuItem(value: 'weekly', child: Text("Every Week")),
                    DropdownMenuItem(value: 'monthly', child: Text("Every Month")),
                    DropdownMenuItem(value: 'custom', child: Text("Every X Days")),
                  ],
                  onChanged: (v) => setState(() => recurrence = v!),
                ),
                
                if (recurrence == 'custom')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: customDaysController,
                      decoration: const InputDecoration(labelText: "Days Interval (X)"),
                      keyboardType: TextInputType.number,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (itemToEdit != null)
              TextButton(
                onPressed: () async {
                  // Delete
                  itemToEdit.delete();
                  _loadItems();
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text("Delete"),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                if (titleController.text.isNotEmpty && amountController.text.isNotEmpty) {
                  // Construct Final DateTime
                  final finalDateTime = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  );

                  // Construct Rule
                  String finalRule = recurrence;
                  if (recurrence == 'custom') {
                    final days = int.tryParse(customDaysController.text) ?? 1;
                    finalRule = 'custom_days_$days';
                  }

                  if (itemToEdit != null) {
                    // Update existing
                    itemToEdit.title = titleController.text;
                    itemToEdit.amount = double.tryParse(amountController.text) ?? 0.0;
                    itemToEdit.recurrenceRule = finalRule;
                    itemToEdit.nextDueDate = finalDateTime;
                    await itemToEdit.save();
                  } else {
                    // Create new
                    await _service.addSchedule(
                      title: titleController.text,
                      amount: double.tryParse(amountController.text) ?? 0.0,
                      recurrenceRule: finalRule,
                      nextDueDate: finalDateTime,
                      isFavorite: false, 
                    );
                  }
                  
                  _loadItems();
                  if (mounted) Navigator.pop(context);
                }
              },
              child: Text(itemToEdit == null ? "Add" : "Save"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Upcoming Income",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _showAddScheduleDialog(),
                tooltip: "Add Schedule",
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _items.isEmpty 
              ? const Center(child: Text("No upcoming income scheduled."))
              : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                final now = DateTime.now();
                final isOverdue = item.nextDueDate.isBefore(now);
                final isToday = item.nextDueDate.year == now.year && 
                                item.nextDueDate.month == now.month && 
                                item.nextDueDate.day == now.day;
                
                Color statusColor = Colors.grey;
                if (isOverdue || isToday) statusColor = Colors.red;
                else if (item.nextDueDate.isAfter(now)) statusColor = Colors.green;

                return ListTile(
                  onTap: () => _showAddScheduleDialog(itemToEdit: item),
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.1),
                    child: Icon(Icons.attach_money, color: statusColor),
                  ),
                  title: Text(item.title),
                  subtitle: Text("${DateFormat('dd MMM yyyy HH:mm').format(item.nextDueDate)} (${item.recurrenceRule})"),
                  trailing: Text(
                    NumberFormat('#,##0.00').format(item.amount),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
