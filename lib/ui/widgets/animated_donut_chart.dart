import 'package:flutter/material.dart';
import 'dart:math';
import '../../models/transaction.dart';
import '../../utils/category_styles.dart';

class AnimatedDonutChart extends StatefulWidget {
  final List<Transaction> transactions;
  final double total;
  final double size;

  const AnimatedDonutChart({
    super.key,
    required this.transactions,
    required this.total,
    this.size = 220,
  });

  @override
  State<AnimatedDonutChart> createState() => _AnimatedDonutChartState();
}

class _AnimatedDonutChartState extends State<AnimatedDonutChart> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedDonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.total != widget.total) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Prepare Data Sections
    Map<String, double> categoryTotals = {};
    for (var t in widget.transactions) {
      categoryTotals[t.category ?? 'Uncategorized'] = 
          (categoryTotals[t.category ?? 'Uncategorized'] ?? 0) + t.price;
    }

    final totalExpense = widget.total;
    final sections = categoryTotals.entries.map((e) {
      return _ChartSection(
        value: e.value,
        color: CategoryStyles.getColor(e.key),
      );
    }).toList();
    
    // Sort so largest segments are drawn first/logically
    sections.sort((a, b) => b.value.compareTo(a.value));

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value, // Expand from 0 to 1
          child: CustomPaint(
            painter: _DonutChartPainter(
              sections: sections,
              total: totalExpense > 0 ? totalExpense : 1, // Prevent div/0
              progress: _animation.value, // Draw progress
              strokeWidth: 24, // Thick modern stroke
            ),
            child: SizedBox(
              height: widget.size,
              width: widget.size,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Total Balance",
                      style: TextStyle(
                        fontSize: widget.size * 0.06, // Responsive font
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "฿${widget.total.toStringAsFixed(0)}", // Remove decimals for space
                      style: TextStyle(
                        fontSize: widget.size * 0.12, // Responsive font
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                        letterSpacing: -1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChartSection {
  final double value;
  final Color color;
  _ChartSection({required this.value, required this.color});
}

class _DonutChartPainter extends CustomPainter {
  final List<_ChartSection> sections;
  final double total;
  final double progress;
  final double strokeWidth;

  _DonutChartPainter({
    required this.sections,
    required this.total,
    required this.progress,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    
    // Draw Background Ring
    final bgPaint = Paint()
      ..color = Colors.grey.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    
    canvas.drawCircle(center, radius, bgPaint);

    // Draw Sections
    double startAngle = -pi / 2; // Start from top
    
    for (var section in sections) {
      final sweepAngle = (section.value / total) * 2 * pi * progress;
      
      final paint = Paint()
        ..color = section.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round; // Rounded Caps as requested

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.sections != sections;
  }
}
