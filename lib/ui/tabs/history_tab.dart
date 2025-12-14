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

  @override
  void initState() {
    super.initState();
    box = DatabaseService().transactionBox;
  }
  
  Widget _buildFilterButton(String label, String value, Color color) {
    final isSelected = _filterType == value;
    return GestureDetector(
      onTap: () => setState(() => _filterType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Kanit',
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  // 1. Logic to get filtered transactions
  List<Transaction> _getTransactionsForDay(DateTime day) {
    return box.values.where((tx) {
      return isSameDay(tx.date, day);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date)); // Newest first
  }
  
  // Logic for Monthly Totals (Context for Charts)
  List<Transaction> _getTransactionsForMonth(DateTime month) {
     return box.values
        .where((ts) => ts.date.year == month.year && ts.date.month == month.month)
        .toList();
  }
  
  double _calculateMonthTotal(List<Transaction> transactions) {
    return transactions
      .where((tx) => tx.type == 'expense')
      .fold(0.0, (sum, tx) => sum + tx.price);
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
            // Rule: 'All' -> Show Expense in Chart. 'Expense' -> Expense. 'Income' -> Income.
            final chartFilterType = _filterType == 'income' ? 'income' : 'expense';
            final monthlyTransactions = allMonthlyTransactions
                .where((tx) => tx.type == chartFilterType)
                .toList();
                
            final monthlyTotal = monthlyTransactions.fold(0.0, (sum, tx) => sum + tx.price);
            
            // 1. Calculate Category Stats
            final Map<String, double> categoryStats = {};
            for (var tx in monthlyTransactions) {
              final cat = tx.category ?? 'Uncategorized';
              categoryStats[cat] = (categoryStats[cat] ?? 0) + tx.price;
            }
            // Convert to List & Sort
            final sortedCategories = categoryStats.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            
            return Column(
              children: [
                // ==========================================
                // 1. Header Section: Month Title & Chart
                // ==========================================
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Column(
                    children: [
                      // Header Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Previous Month
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1);
                              });
                            },
                            icon: Icon(Icons.chevron_left, color: colorScheme.onSurfaceVariant),
                            visualDensity: VisualDensity.compact,
                          ),
                          
                          // Month Title
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                "ภาพรวม", 
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant, 
                                  fontSize: 12,
                                  fontFamily: 'Kanit'
                                ),
                              ),
                              Text(
                                DateFormat('MMMM yyyy').format(_focusedDay),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Kanit',
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),

                          // Next Month + Toggle Stacked/Row
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1);
                                  });
                                },
                                icon: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
                                visualDensity: VisualDensity.compact,
                              ),
                              // Toggle Button removed as per user request (Gesture control enabled)
                            ],
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // 2. New Side-by-Side Layout
                        
                      // 2. New Side-by-Side Layout
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: Chart
                          AnimatedDonutChart(
                            transactions: monthlyTransactions,
                            total: monthlyTotal,
                            size: 160, // Smaller size for split view
                          ),
                          
                          const SizedBox(width: 16),
                          
                          // Right: Scrollable Category List
                          Expanded(
                            child: SizedBox(
                              height: 160, // Match chart height
                              child: sortedCategories.isEmpty 
                              ? Center(
                                  child: Text(
                                    "No Data", 
                                    style: TextStyle(color: colorScheme.outlineVariant)
                                  ),
                                )
                              : ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: sortedCategories.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final catName = sortedCategories[index].key;
                                    final catTotal = sortedCategories[index].value;
                                    
                                    return Row(
                                      children: [
                                        // Icon Dot
                                        Container(
                                          width: 8, height: 8,
                                          decoration: BoxDecoration(
                                            color: CategoryStyles.getColor(catName),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Name
                                        Expanded(
                                          child: Text(
                                            CategoryStyles.getThaiName(catName),
                                            style: TextStyle(
                                              fontFamily: 'Kanit',
                                              fontSize: 14,
                                              color: colorScheme.onSurface,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Amount
                                        Text(
                                          NumberFormat('#,##0').format(catTotal),
                                          style: TextStyle(
                                            fontFamily: 'Manrope', // Monospace-ish for numbers
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                            ),
                          ),
                      ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Filter Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildFilterButton("ทั้งหมด", 'all', colorScheme.primary),
                          const SizedBox(width: 12),
                          _buildFilterButton("รายรับ", 'income', Colors.green),
                          const SizedBox(width: 12),
                          _buildFilterButton("รายจ่าย", 'expense', colorScheme.error),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ==========================================
                // 2. Expandable Calendar Strip
                // ==========================================
                GestureDetector(
                  onVerticalDragEnd: (details) {
                    if (details.primaryVelocity! > 0) {
                      // Swipe Down -> Expand to Month
                      if (_calendarFormat != CalendarFormat.month) {
                        setState(() => _calendarFormat = CalendarFormat.month);
                      }
                    } else if (details.primaryVelocity! < 0) {
                      // Swipe Up -> Collapse to Week
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
                            rowHeight: 60, // Taller for icons
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
                                
                                // Sort by price desc
                                txs.sort((a, b) => b.price.compareTo(a.price));
                                final top3 = txs.take(3).toList();

                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: top3.map((tx) {
                                    return Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 1),
                                      child: Icon(
                                        CategoryStyles.getIcon(tx.category ?? 'Other'),
                                        size: 6, // Minimal dot size 
                                        color: CategoryStyles.getColor(tx.category ?? 'Other'),
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
                                      borderRadius: BorderRadius.circular(14), // Squircle
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
                              // Sync focus when swiping
                              setState(() {
                                _focusedDay = focusedDay;
                              });
                            },
                          ),
                        ),
                        
                        // Drag Handle
                        Center(
                          child: Container(
                            width: 32,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(2),
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
                Expanded(
                  child: GestureDetector(
                    onHorizontalDragEnd: (details) {
                      if (details.primaryVelocity! > 0) {
                        // Swipe Right -> Previous Day
                        setState(() {
                          _selectedDay = _selectedDay?.subtract(const Duration(days: 1));
                          _focusedDay = _selectedDay ?? _focusedDay;
                        });
                      } else if (details.primaryVelocity! < 0) {
                        // Swipe Left -> Next Day
                        setState(() {
                          _selectedDay = _selectedDay?.add(const Duration(days: 1));
                          _focusedDay = _selectedDay ?? _focusedDay;
                        });
                      }
                    },
                    child: Container(
                      color: theme.cardTheme.color, 
                      child: Builder( // Filter Logic inside main builder
                        builder: (context) {
                          var dailyTransactions = _selectedDay != null 
                              ? box.values.where((tx) => isSameDay(tx.date, _selectedDay!)).toList()
                              : <Transaction>[];
                          
                          // Filter by Type
                          if (_filterType != 'all') {
                            dailyTransactions = dailyTransactions
                                .where((tx) => tx.type == _filterType)
                                .toList();
                          }
                          
                          // 1. Sort & Group
                          dailyTransactions.sort((a, b) => b.date.compareTo(a.date));
                          
                          final Map<String, List<Transaction>> groupedTransactions = {};
                          for (var tx in dailyTransactions) {
                            final cat = tx.category ?? 'Uncategorized';
                            if (!groupedTransactions.containsKey(cat)) {
                              groupedTransactions[cat] = [];
                            }
                            groupedTransactions[cat]!.add(tx);
                          }

                          // 2. Sort Groups by Total Amount (Desc)
                          final sortedGroupKeys = groupedTransactions.keys.toList()
                            ..sort((k1, k2) {
                              final total1 = groupedTransactions[k1]!.fold(0.0, (sum, t) => sum + t.price);
                              final total2 = groupedTransactions[k2]!.fold(0.0, (sum, t) => sum + t.price);
                              return total2.compareTo(total1);
                            });

                          // 3. Keep Daily Stats
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
                                Container(
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
                                      
                                      // Stats Row (Side by Side)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Income Pill (if exists)
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
                                            
                                          // Expense Pill
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

                              // Transaction List
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: dailyTransactions.isEmpty
                                      ? PremiumEmptyState(
                                          key: ValueKey('empty_\$_selectedDay'), // Force refresh on day change
                                          message: "ไม่มีรายการ",
                                          subMessage: "เลือกวันที่อื่น หรือกด + เพื่อเพิ่ม",
                                        )
                                      : ListView.builder(
                                          key: ValueKey(_selectedDay),
                                          padding: const EdgeInsets.only(bottom: 80, top: 0),
                                          itemCount: sortedGroupKeys.length,
                                          itemBuilder: (context, index) {
                                            final catName = sortedGroupKeys[index];
                                            final txs = groupedTransactions[catName]!;
                                            
                                            // 1. Single Item -> Normal Tile
                                            if (txs.length == 1) {
                                               return TransactionListItem(
                                                  transaction: txs.first,
                                                  onTap: () => _showEditDialog(context, txs.first),
                                                  showDivider: true,
                                                );
                                            }
                                            
                                            // 2. Multiple Items -> Group Expansion Tile
                                            final groupTotal = txs.fold(0.0, (sum, t) => sum + t.price);
                                            final isExpense = txs.any((t) => t.type == 'expense');
                                            
                                            return Card(
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
            );
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
                  // Slip Image (If available)
                  if (transaction.slipImagePath != null && File(transaction.slipImagePath!).existsSync())
                    GestureDetector(
                      onTap: () {
                        // Show full screen image
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

                  // Date Picker
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
                  
                  // Item Name
                  TextFormField(
                    controller: itemController,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อรายการ',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Price & Qty
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

                  // Category
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
              // Delete Button
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
                  
                  if (confirm == true && context.mounted) {
                    transaction.delete(); // Hive delete
                    Navigator.pop(context);
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text("ลบรายการ"),
              ),
              
              // Cancel
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("ยกเลิก"),
              ),
              
              // Save
              ElevatedButton(
                onPressed: () {
                  transaction.item = itemController.text;
                  transaction.price = double.tryParse(priceController.text) ?? transaction.price;
                  transaction.qty = double.tryParse(qtyController.text) ?? 1.0;
                  transaction.category = selectedCategory;
                  transaction.date = selectedDate;
                  transaction.save(); // Hive save
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
}
