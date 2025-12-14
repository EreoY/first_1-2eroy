import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_global_provider.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger initialization immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppGlobalProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen to provider state
    final appProvider = context.watch<AppGlobalProvider>();

    // Check if AI is loaded
    if (appProvider.isAIModelLoaded) {
      // Navigate to Home Screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Add a small delay for the animation to be appreciated or ensuring smooth transition
        Future.delayed(const Duration(milliseconds: 500), () {
          if (context.mounted) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 800),
              ),
            );
          }
        });
      });
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A), // Slate 900
              Color(0xFF1E1B4B), // Indigo 950
              Color(0xFF312E81), // Indigo 900
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. Animated Logo
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(seconds: 2),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigoAccent.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: MinimalistBrainPainter(),
                  ),
                ),
              ),
              
              const SizedBox(height: 48),
              
              // 2. Text Animation
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  children: [
                    const Text(
                      "QUICK EXPENSE",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.0,
                        fontFamily: 'Manrope', // Ensure this font is used as per main.dart
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "AI-Powered Tracker",
                      style: TextStyle(
                        color: Colors.indigo[200],
                        fontSize: 14,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 64),
              
              // 3. Status & Loading
              SizedBox(
                width: 150,
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigoAccent),
                      minHeight: 2,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Initializing System...",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Minimalist Brain Logo Painter
class MinimalistBrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;
    final double cy = h / 2;

    // Draw Brain Outline (Abstract Hexagonal/Rounded Shape)
    final Path path = Path();
    
    // Left Lobe
    path.moveTo(cx - 10, cy - 25);
    path.cubicTo(
      cx - 40, cy - 25, 
      cx - 40, cy + 25, 
      cx - 10, cy + 25
    );
    
    // Right Lobe
    path.moveTo(cx + 10, cy - 25);
    path.cubicTo(
      cx + 40, cy - 25, 
      cx + 40, cy + 25, 
      cx + 10, cy + 25
    );

    // Connection (Corpus Callosum) - Digital Lines
    canvas.drawPath(path, paint);

    // Center Connections (Nodes)
    final paintNodes = Paint()
      ..color = Colors.indigoAccent
      ..style = PaintingStyle.fill;
      
    canvas.drawCircle(Offset(cx, cy - 10), 4, paintNodes);
    canvas.drawCircle(Offset(cx, cy + 10), 4, paintNodes);
    
    // Circuit Lines
    paint.strokeWidth = 1.5;
    paint.color = Colors.white.withOpacity(0.5);
    
    canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy + 10), paint);
    canvas.drawLine(Offset(cx - 25, cy), Offset(cx + 25, cy), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
