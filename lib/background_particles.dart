import 'dart:math';
import 'package:flutter/material.dart';

class MoodParticleBackground extends StatelessWidget {
  final bool show;
  const MoodParticleBackground({super.key, required this.show});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    
    return RepaintBoundary(
      child: CustomPaint(
        painter: MoodParticlePainter(),
        size: Size.infinite,
      ),
    );
  }
}

class MoodParticlePainter extends CustomPainter {
  final List<_Particle> particles = List.generate(25, (_) => _Particle());
  final double speed = 0.2;

  @override
  void paint(Canvas canvas, Size size) {
    // We'll use the current time to drive motion without a separate AnimationController
    // if possible, but for smooth particles, a basic loop is better.
    // However, to save battery on Redmi 6A, we'll use a very simple approach.
    final rand = Random(42); // fixed seed for consistency
    final paint = Paint()..color = Colors.white.withOpacity(0.05);

    for (int i = 0; i < 30; i++) {
      // Basic deterministic "drift" based on index
      final phase = DateTime.now().millisecondsSinceEpoch / 2000.0;
      final x = (rand.nextDouble() * size.width + sin(phase + i) * 20) % size.width;
      final y = (rand.nextDouble() * size.height + cos(phase * 0.5 + i) * 30) % size.height;
      final radius = rand.nextDouble() * 1.5 + 0.5;
      
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true; 
}

class _Particle {
  // Simple structure for future enhancement if needed
}
