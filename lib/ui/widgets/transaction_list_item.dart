import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../utils/category_styles.dart';

class TransactionListItem extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback onTap;
  final bool showDivider;

  const TransactionListItem({
    super.key,
    required this.transaction,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    final category = transaction.category ?? 'Uncategorized';
    final categoryColor = CategoryStyles.getColor(category);
    final categoryIcon = CategoryStyles.getIcon(category);
    
    final isIncome = transaction.type == 'income';
    
    // Formatting currency
    final currencyFormat = NumberFormat("#,##0.00", "th");
    
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), // Spacious padding
        child: Row(
          children: [
            // 1. Premium Icon (Squircle)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark 
                    ? categoryColor.withOpacity(0.15) 
                    : categoryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16), // Softer curve
                // No border for cleaner look
              ),
              child: Icon(
                categoryIcon,
                color: categoryColor,
                size: 24,
              ),
            ),
            
            const SizedBox(width: 16),
            
            // 2. Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          transaction.item,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((transaction.qty ?? 1) > 1)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "x${transaction.qty!.toInt()}",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // Time
                      Text(
                        DateFormat('HH:mm').format(transaction.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.circle, size: 3, color: colorScheme.outline),
                      ),
                      // Category Name
                      Expanded(
                        child: Text(
                          CategoryStyles.getThaiName(category),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Note icon if present
                      if (transaction.note != null && transaction.note!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.note_alt_outlined, size: 12, color: colorScheme.outline),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // 3. Price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${isIncome ? '+' : '-'} ${currencyFormat.format(transaction.price)}",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold, // Enhanced weight
                    fontFamily: PlatformUtils.isAndroid ? 'monospace' : null, // Monospace for numbers looks fin-tech
                    color: isIncome 
                        ? const Color(0xFF10B981) // Emerald Green
                        : (isDark ? const Color(0xFFF43F5E) : const Color(0xFFE11D48)), // Rose Red
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PlatformUtils {
  static bool get isAndroid => true; // Simplified for this context
}
