import 'package:flutter/material.dart';
import 'dart:math';
import 'package:intl/intl.dart';
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
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart);
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
    // 1. Prepare Data
    Map<String, double> categoryTotals = {};
    for (var t in widget.transactions) {
      categoryTotals[t.category ?? 'Uncategorized'] = 
          (categoryTotals[t.category ?? 'Uncategorized'] ?? 0) + t.price;
    }

    // Sort Descending
    final sections = categoryTotals.entries.map((e) {
      return _ChartSection(
        key: e.key,
        value: e.value,
        color: CategoryStyles.getColor(e.key),
      );
    }).toList()..sort((a, b) => b.value.compareTo(a.value));
    
    final total = widget.total > 0 ? widget.total : 1.0;
    
    // Layout Constants
    final chartRadius = widget.size * 0.38; // Maximized radius within fit

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Chart Painter (Glow + Arcs)
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _HeroDonutPainter(
                  sections: sections,
                  total: total,
                  progress: _animation.value,
                  chartRadius: chartRadius,
                ),
              ),

              // 2. Center Text (Hero)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("ยอดรวม", style: TextStyle(fontSize: 14, color: Colors.grey, fontFamily: 'Kanit')),
                  Text(
                    NumberFormat.compact().format(widget.total), 
                    style: TextStyle(
                      fontSize: 32, // Huge text
                      fontWeight: FontWeight.w900, // Boldest
                      color: Theme.of(context).colorScheme.onSurface,
                      fontFamily: 'Manrope',
                      letterSpacing: -1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChartSection {
  final String key;
  final double value;
  final Color color;
  _ChartSection({required this.key, required this.value, required this.color});
}

class _HeroDonutPainter extends CustomPainter {
  final List<_ChartSection> sections;
  final double total;
  final double progress;
  final double chartRadius;

  _HeroDonutPainter({
    required this.sections,
    required this.total,
    required this.progress,
    required this.chartRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = 35.0;
    
    // 1. Background Ring (Faded)
    final bgPaint = Paint()
      ..color = Colors.grey.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth - 5; // Slightly thinner than data
    
    canvas.drawCircle(center, chartRadius, bgPaint);

    double startAngle = -pi / 2;
    
    for (var section in sections) {
      final sweepAngle = (section.value / total) * 2 * pi * progress;
      
      // Main Arc Paint (Sharp & Clean)
      final paint = Paint()
        ..color = section.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt; // Sharp edges

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: chartRadius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _HeroDonutPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
