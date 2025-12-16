import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:table_calendar/table_calendar.dart';
import '../../models/transaction.dart';
import '../../services/database_service.dart';
import '../../utils/category_styles.dart';
import '../widgets/animated_donut_chart.dart';
import '../widgets/transaction_list_item.dart';
import '../widgets/premium_empty_state.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  // Calendar State
  CalendarFormat _calendarFormat = CalendarFormat.week;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now(); // Default filter
  String _filterType = 'all'; // 'all', 'expense', 'income'

  late final Box<Transaction> box;
  bool _isSummaryVisible = true;

  @override
  void initState() {
    super.initState();
    box = DatabaseService().transactionBox;
    // Load persisted state
    final settings = DatabaseService().settingsBox;
    _isSummaryVisible = settings.get('history_summary_visible', defaultValue: true);
  }

  Widget _buildFilterTab(IconData icon, String value, Color color, String label) {
    final isSelected = _filterType == value;
    final isExpanded = !_isSummaryVisible;

    return GestureDetector(
      onTap: () => setState(() => _filterType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Reduced padding
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? color : Colors.grey[400],
            ),
            if (isExpanded) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Kanit',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Logic for Monthly Totals (Context for Charts)
  List<Transaction> _getTransactionsForMonth(DateTime month) {
     return box.values
        .where((ts) => ts.date.year == month.year && ts.date.month == month.month)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: box.listenable(),
          builder: (context, Box<Transaction> box, _) {
            // Data Prep
            final allMonthlyTransactions = _getTransactionsForMonth(_focusedDay);
            
            // Filter for Chart/Category Display
            final chartFilterType = _filterType == 'income' ? 'income' : 'expense';
            final monthlyTransactions = allMonthlyTransactions
                .where((tx) => tx.type == chartFilterType)
                .toList();
                
            final monthlyTotal = monthlyTransactions.fold(0.0, (sum, tx) => sum + tx.price);
            
            // Calculate Category Stats
            final Map<String, double> categoryStats = {};
            for (var tx in monthlyTransactions) {
              final cat = tx.category ?? 'Uncategorized';
              categoryStats[cat] = (categoryStats[cat] ?? 0) + tx.price;
            }
            // Convert to List & Sort
            final sortedCategories = categoryStats.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            
            return SingleChildScrollView(
              child: Column(
                children: [
                  // ==========================================
                  // 1. Header Section: Month Title & Chart
                  // ==========================================
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        // 1. Header Row (Month Title)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1)),
                                icon: Icon(Icons.chevron_left, color: colorScheme.onSurfaceVariant),
                                visualDensity: VisualDensity.compact,
                              ),
                              Column(
                                children: [
                                  Text("ภาพรวม", style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, fontFamily: 'Kanit')),
                                  Text(
                                    DateFormat('MMMM yyyy').format(_focusedDay),
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Kanit', color: colorScheme.onSurface),
                                  ),
                                ],
                              ),
                              IconButton(
                                onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1)),
                                icon: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16),
  
                        // 2. Fragmented Control (Filters)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              _buildSegmentButton('all', 'ทั้งหมด'),
                              _buildSegmentButton('income', 'รายรับ'),
                              _buildSegmentButton('expense', 'รายจ่าย'),
                            ],
                          ),
                        ),
  
                        const SizedBox(height: 16), // Reduced height
                        
                        // 3. Main Content: Big Chart (Centered)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
                            child: AnimatedDonutChart(
                              transactions: monthlyTransactions,
                              total: monthlyTotal,
                              size: 210, // Adjusted size to fit screen better
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 16), // Reduced height

                      // 4. Legend (Grid Below Chart)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: sortedCategories.take(6).map((e) {
                            final pct = monthlyTotal > 0 ? (e.value / monthlyTotal * 100) : 0.0;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    color: CategoryStyles.getColor(e.key),
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: CategoryStyles.getColor(e.key).withOpacity(0.4), blurRadius: 4)]
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  CategoryStyles.getThaiName(e.key),
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${pct.toStringAsFixed(0)}%',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ==========================================
                // 2. Expandable Calendar Strip
                // ==========================================
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (details) {
                    if (details.delta.dy > 5) {
                      if (_calendarFormat != CalendarFormat.month) {
                        setState(() => _calendarFormat = CalendarFormat.month);
                      }
                    } else if (details.delta.dy < -5) {
                      if (_calendarFormat != CalendarFormat.week) {
                        setState(() => _calendarFormat = CalendarFormat.week);
                      }
                    }
                  },
                  onVerticalDragEnd: (details) {
                    if (details.primaryVelocity! > 0) {
                      if (_calendarFormat != CalendarFormat.month) {
                        setState(() => _calendarFormat = CalendarFormat.month);
                      }
                    } else if (details.primaryVelocity! < 0) {
                      if (_calendarFormat != CalendarFormat.week) {
                        setState(() => _calendarFormat = CalendarFormat.week);
                      }
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.cardTheme.color,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Calendar Widget
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: TableCalendar(
                            firstDay: DateTime(2020),
                            lastDay: DateTime.now().add(const Duration(days: 365)),
                            focusedDay: _focusedDay,
                            calendarFormat: _calendarFormat,
                            
                            // Style & Formatting
                            headerVisible: false,
                            daysOfWeekHeight: 24,
                            rowHeight: 60,
                            startingDayOfWeek: StartingDayOfWeek.monday,
                            
                            calendarStyle: CalendarStyle(
                              outsideDaysVisible: false,
                              defaultTextStyle: TextStyle(fontFamily: 'Kanit', color: colorScheme.onSurface),
                              weekendTextStyle: TextStyle(fontFamily: 'Kanit', color: colorScheme.error.withOpacity(0.7)),
                            ),
                            
                            // Custom Builders
                            calendarBuilders: CalendarBuilders(
                              // Marker Builder (Top 3 Icons)
                              markerBuilder: (context, date, events) {
                                final txs = box.values.where((t) => isSameDay(t.date, date) && t.type == 'expense').toList();
                                if (txs.isEmpty) return null;
                                
                                // Group by category and sum prices
                                final Map<String, double> categoryTotals = {};
                                for (var tx in txs) {
                                  final cat = tx.category ?? 'Other';
                                  categoryTotals[cat] = (categoryTotals[cat] ?? 0) + tx.price;
                                }

                                // Sort by total amount desc
                                final sortedCategories = categoryTotals.entries.toList()
                                  ..sort((a, b) => b.value.compareTo(a.value));
                                  
                                final top3WithKey = sortedCategories.take(3).toList();

                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: top3WithKey.map((entry) {
                                    final cat = entry.key;
                                    return Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 1),
                                      child: Icon(
                                        CategoryStyles.getIcon(cat),
                                        size: 6, // Minimal dot size 
                                        color: CategoryStyles.getColor(cat),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },

                              selectedBuilder: (context, date, events) {
                                return Center(
                                  child: Container(
                                    width: 40, height: 40,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.primary.withOpacity(0.4),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      '${date.day}',
                                      style: const TextStyle(
                                        color: Colors.white, 
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Kanit'
                                      ),
                                    ),
                                  ),
                                );
                              },
                              todayBuilder: (context, date, events) {
                                return Center(
                                  child: Container(
                                    width: 40, height: 40,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        color: colorScheme.primary, 
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Kanit'
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            
                            // Interaction
                            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                            onDaySelected: (selectedDay, focusedDay) {
                              setState(() {
                                _selectedDay = selectedDay;
                                _focusedDay = focusedDay; 
                                if (_calendarFormat == CalendarFormat.month) {
                                  _calendarFormat = CalendarFormat.week;
                                }
                              });
                            },
                            onFormatChanged: (format) {
                               if (_calendarFormat != format) {
                                 setState(() => _calendarFormat = format);
                               }
                            },
                            onPageChanged: (focusedDay) {
                              setState(() {
                                _focusedDay = focusedDay;
                              });
                            },
                          ),
                        ),
                        
                        // Drag Handle
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            alignment: Alignment.center,
                            child: Container(
                              width: 32,
                              height: 4,
                              decoration: BoxDecoration(
                                color: colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ==========================================
                // 3. Transaction List (Flexible)
                // ==========================================
                Container(
                  child: GestureDetector(
                    onHorizontalDragEnd: (details) {
                      if (details.primaryVelocity! > 0) {
                        setState(() {
                          _selectedDay = _selectedDay?.subtract(const Duration(days: 1));
                          _focusedDay = _selectedDay ?? _focusedDay;
                        });
                      } else if (details.primaryVelocity! < 0) {
                        setState(() {
                          _selectedDay = _selectedDay?.add(const Duration(days: 1));
                          _focusedDay = _selectedDay ?? _focusedDay;
                        });
                      }
                    },
                    child: Container(
                      color: theme.cardTheme.color, 
                      child: Builder(
                        builder: (context) {
                          var dailyTransactions = _selectedDay != null 
                              ? box.values.where((tx) => isSameDay(tx.date, _selectedDay!)).toList()
                              : <Transaction>[];
                          
                          if (_filterType != 'all') {
                            dailyTransactions = dailyTransactions
                                .where((tx) => tx.type == _filterType)
                                .toList();
                          }
                          
                          dailyTransactions.sort((a, b) => b.date.compareTo(a.date));
                          
                          final Map<String, List<Transaction>> groupedTransactions = {};
                          for (var tx in dailyTransactions) {
                            final cat = tx.category ?? 'Uncategorized';
                            if (!groupedTransactions.containsKey(cat)) {
                              groupedTransactions[cat] = [];
                            }
                            groupedTransactions[cat]!.add(tx);
                          }

                          final sortedGroupKeys = groupedTransactions.keys.toList()
                            ..sort((k1, k2) {
                              final total1 = groupedTransactions[k1]!.fold(0.0, (sum, t) => sum + t.price);
                              final total2 = groupedTransactions[k2]!.fold(0.0, (sum, t) => sum + t.price);
                              return total2.compareTo(total1);
                            });

                          final dailyExpense = dailyTransactions
                              .where((tx) => tx.type == 'expense')
                              .fold(0.0, (sum, tx) => sum + tx.price);
                          
                          final dailyIncome = dailyTransactions
                              .where((tx) => tx.type == 'income')
                              .fold(0.0, (sum, tx) => sum + tx.price);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Daily Summary Header
                              if (_selectedDay != null)
                                SlideFadeTransition(
                                  index: 0,
                                  delay: const Duration(milliseconds: 50),
                                  child: Container(
                                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.03),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        )
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        // Date
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.primaryContainer,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Text(
                                                  DateFormat('d').format(_selectedDay!),
                                                  style: TextStyle(
                                                    fontFamily: 'Manrope',
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme.primary,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    DateFormat('EEEE').format(_selectedDay!),
                                                    style: TextStyle(
                                                      fontFamily: 'Kanit',
                                                      fontSize: 12,
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  Text(
                                                    DateFormat('MMM yyyy').format(_selectedDay!),
                                                    style: TextStyle(
                                                      fontFamily: 'Manrope',
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: colorScheme.onSurface,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        
                                        // Stats Row
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (dailyIncome > 0) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  "+ ${NumberFormat('#,##0').format(dailyIncome)}",
                                                  style: const TextStyle(
                                                    fontFamily: 'Manrope',
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                              
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: colorScheme.error.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                "- ${NumberFormat('#,##0').format(dailyExpense)}",
                                                style: TextStyle(
                                                  fontFamily: 'Manrope',
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: colorScheme.error,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // Transaction List
                              Container(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: dailyTransactions.isEmpty
                                      ? PremiumEmptyState(
                                          key: ValueKey('empty_\$_selectedDay'),
                                          message: "ไม่มีรายการ",
                                          subMessage: "เลือกวันที่อื่น หรือกด + เพื่อเพิ่ม",
                                        )
                                      : ListView.builder(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          key: ValueKey(_selectedDay),
                                          padding: const EdgeInsets.only(bottom: 80, top: 0),
                                          itemCount: sortedGroupKeys.length,
                                          itemBuilder: (context, index) {
                                            final catName = sortedGroupKeys[index];
                                            final txs = groupedTransactions[catName]!;
                                            
                                            Widget child;
                                            
                                            if (txs.length == 1) {
                                               child = TransactionListItem(
                                                  transaction: txs.first,
                                                  onTap: () => _showEditDialog(context, txs.first),
                                                  showDivider: true,
                                                );
                                            } else {
                                              final groupTotal = txs.fold(0.0, (sum, t) => sum + t.price);
                                              final isExpense = txs.any((t) => t.type == 'expense');
                                              
                                              child = Card(
                                                elevation: 0,
                                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                                color: Theme.of(context).cardColor,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)),
                                                ),
                                                child: Theme(
                                                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                                  child: ExpansionTile(
                                                    tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                                    leading: Container(
                                                      width: 12, height: 12,
                                                      decoration: BoxDecoration(
                                                        color: CategoryStyles.getColor(catName),
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    title: Text(
                                                      CategoryStyles.getThaiName(catName),
                                                      style: const TextStyle(
                                                        fontFamily: 'Kanit',
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                    subtitle: Text(
                                                      "${txs.length} รายการ",
                                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                                    ),
                                                    trailing: Text(
                                                      NumberFormat('#,##0').format(groupTotal),
                                                      style: TextStyle(
                                                        fontFamily: 'Manrope',
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                        color: isExpense ? colorScheme.error : Colors.green,
                                                      ),
                                                    ),
                                                    children: txs.map((tx) {
                                                      return Container(
                                                        decoration: BoxDecoration(
                                                          border: Border(
                                                            top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.2)),
                                                          ),
                                                        ),
                                                        child: TransactionListItem(
                                                          transaction: tx,
                                                          onTap: () => _showEditDialog(context, tx),
                                                          showDivider: false,
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ),
                                              );
                                            }

                                            return SlideFadeTransition(
                                              index: index + 1,
                                              delay: const Duration(milliseconds: 50),
                                              child: child,
                                            );
                                          },
                                        ),
                                  ),
                                ),
                              ],
                            );
                        }
                      ),
                    ),
                  ),
                ),
              ],
            ));
          },
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, Transaction transaction) {
    final itemController = TextEditingController(text: transaction.item);
    final priceController = TextEditingController(text: transaction.price.toString());
    final qtyController = TextEditingController(text: (transaction.qty ?? 1).toString());
    String selectedCategory = transaction.category ?? 'Uncategorized';
    DateTime selectedDate = transaction.date;

    final categories = [
      'Food', 'Transport', 'Shopping', 'Bills', 'Transfer', 
      'Entertainment', 'Health', 'Salary', 'Other', 'Uncategorized'
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("แก้ไขรายการ"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (transaction.slipImagePath != null && File(transaction.slipImagePath!).existsSync())
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => Dialog(
                            backgroundColor: Colors.transparent,
                            insetPadding: EdgeInsets.zero,
                            child: Stack(
                              children: [
                                InteractiveViewer(
                                  child: Image.file(File(transaction.slipImagePath!)),
                                ),
                                Positioned(
                                  top: 40,
                                  right: 20,
                                  child: IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                    onPressed: () => Navigator.pop(ctx),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: DecorationImage(
                            image: FileImage(File(transaction.slipImagePath!)),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.black.withOpacity(0.1),
                          ),
                          child: const Center(
                            child: Icon(Icons.zoom_in, color: Colors.white, size: 32),
                          ),
                        ),
                      ),
                    ),

                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        if (context.mounted) {
                          final time = await showTimePicker(
                            context: context, 
                            initialTime: TimeOfDay.fromDateTime(selectedDate)
                          );
                          if (time != null) {
                            setState(() {
                              selectedDate = DateTime(
                                picked.year, picked.month, picked.day, 
                                time.hour, time.minute
                              );
                            });
                          }
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(selectedDate),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: itemController,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อรายการ',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'ราคา',
                            border: OutlineInputBorder(),
                            prefixText: '฿',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: qtyController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'จำนวน',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: categories.contains(selectedCategory) ? selectedCategory : 'Uncategorized',
                    decoration: const InputDecoration(
                      labelText: 'หมวดหมู่',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: categories.map((c) => DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          Icon(CategoryStyles.getIcon(c), size: 16, color: CategoryStyles.getColor(c)),
                          const SizedBox(width: 8),
                          Text(CategoryStyles.getThaiName(c)),
                        ],
                      ),
                    )).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedCategory = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("ลบรายการ?"),
                      content: const Text("คุณต้องการลบรายการนี้ใช่หรือไม่?"),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ไม่")),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true), 
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text("ลบ"),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirm == true) {
                    await transaction.delete();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text("ลบรายการ"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("ยกเลิก"),
              ),
              ElevatedButton(
                onPressed: () {
                  transaction.item = itemController.text;
                  transaction.price = double.tryParse(priceController.text) ?? transaction.price;
                  transaction.qty = double.tryParse(qtyController.text) ?? 1;
                  transaction.category = selectedCategory;
                  transaction.date = selectedDate;
                  transaction.save();
                  Navigator.pop(context);
                },
                child: const Text("บันทึก"),
              ),
            ],
          );
        },
      ),
    );
  }
  Widget _buildSegmentButton(String key, String label) {
    final isSelected = _filterType == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filterType = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isSelected 
              ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
              : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Kanit',
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class SlideFadeTransition extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final Duration duration;
  final double offset;
  final Curve curve;

  const SlideFadeTransition({
    super.key,
    required this.child,
    required this.index,
    this.delay = const Duration(milliseconds: 50),
    this.duration = const Duration(milliseconds: 400),
    this.offset = 50.0,
    this.curve = Curves.easeOutQuad,
  });

  @override
  State<SlideFadeTransition> createState() => _SlideFadeTransitionState();
}

class _SlideFadeTransitionState extends State<SlideFadeTransition> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
    
    _slideAnimation = Tween<Offset>(begin: Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    Future.delayed(widget.delay * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
