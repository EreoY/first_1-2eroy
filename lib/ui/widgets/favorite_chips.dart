import 'package:flutter/material.dart';
import '../../services/income_scheduler_service.dart';
import '../../models/income_schedule.dart';
import 'package:intl/intl.dart';

class FavoriteChips extends StatefulWidget {
  final Function(IncomeSchedule) onSelected;

  const FavoriteChips({super.key, required this.onSelected});

  @override
  State<FavoriteChips> createState() => _FavoriteChipsState();
}

class _FavoriteChipsState extends State<FavoriteChips> {
  final IncomeSchedulerService _service = IncomeSchedulerService();
  List<IncomeSchedule> _favorites = [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  void _loadFavorites() {
    setState(() {
      _favorites = _service.getFavorites();
    });
  }

  void _showAddDialog() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Quick Template"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty && amountController.text.isNotEmpty) {
                await _service.addSchedule(
                  title: titleController.text,
                  amount: double.tryParse(amountController.text) ?? 0.0,
                  recurrenceRule: 'manual', // Template only
                  nextDueDate: DateTime(2100), // Far future, won't trigger reminder
                  isFavorite: true,
                );
                _loadFavorites();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 60, // Increased height for 2 lines
      child: Row(
        children: [
          // Fixed Add Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showAddDialog,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.add, 
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Reorderable List
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: ReorderableListView(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false, // Remove default handles
                onReorder: (oldIndex, newIndex) async {
                  setState(() {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final item = _favorites.removeAt(oldIndex);
                    _favorites.insert(newIndex, item);
                  });
                  await _service.reorderFavorites(oldIndex, newIndex);
                },
                proxyDecorator: (child, index, animation) {
                  return Material(
                    color: Colors.transparent,
                    child: child,
                  );
                },
                children: _favorites.asMap().entries.map((entry) {
                  final index = entry.key;
                  final fav = entry.value;
                  
                  return ReorderableDragStartListener(
                    key: ValueKey(fav.id),
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => widget.onSelected(fav),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            constraints: const BoxConstraints(minWidth: 80),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fav.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  NumberFormat('#,##0').format(fav.amount),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
