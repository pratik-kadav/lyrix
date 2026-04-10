import 'dart:math';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
//  SEEDED NOISE (Deterministic Hash)
// ─────────────────────────────────────────────────────────────────
double _sn(int seed) {
  int h = seed ^ (seed >>> 16);
  h = (h * 0x45d9f3b) & 0xFFFFFFFF;
  h ^= (h >>> 16);
  return (h / 0x7FFFFFFF).clamp(-1.0, 1.0);
}

enum LyricPhysics { drift, slam }

class ProceduralKineticPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final double progress; // 0.0 to 1.0 (entrance or active state)
  final double delta;    // smoothDelta relative to center (for vertical offset)
  final LyricPhysics physics;
  final int lineIndex;
  final int songHash;
  final double time;     // global time in seconds for Brownian motion

  ProceduralKineticPainter({
    required this.text,
    required this.style,
    required this.progress,
    required this.delta,
    required this.physics,
    required this.lineIndex,
    required this.songHash,
    required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty) return;

    final words = text.split(RegExp(r'\s+'));
    
    // 1. Calculate base layout (Target Positions)
    // For simplicity, we'll do a basic horizontal layout with Wrapping.
    // In a production app, this would be pre-calculated or cached.
    List<_WordLayout> layouts = _calculateLayout(words, size, style);
    
    int charCount = 0;
    final totalChars = text.replaceAll(' ', '').length;

    for (var wordLayout in layouts) {
      // Word-level spatial randomness (Generative)
      // Words avoid the absolute center to create "negative space".
      final wordSeed = wordLayout.index * 13 + lineIndex * 17;
      final spatialX = _sn(wordSeed) * 40.0 * (1.0 - progress);
      final spatialY = _sn(wordSeed + 100) * 30.0 * (1.0 - progress);
      final wordRot  = _sn(wordSeed + 200) * 0.25 * (1.0 - progress);

      // Physics: Brownian Drift (Drift)
      double driftX = 0;
      double driftY = 0;
      if (physics == LyricPhysics.drift) {
        driftX = sin(time * 0.5 + wordLayout.index) * 4.0;
        driftY = cos(time * 0.3 + lineIndex) * 6.0;
      }

      for (int i = 0; i < wordLayout.word.length; i++) {
        final char = wordLayout.word[i];
        
        // Character-level staggering (50ms per index approx)
        // Adjust the 'arrival' point based on character index.
        const staggerFactor = 0.4; // 40% of progress used for staggering
        final charStart = (charCount / max(1, totalChars)) * staggerFactor;
        final charProgress = ((progress - charStart) / (1.0 - staggerFactor)).clamp(0.0, 1.0);
        
        if (charProgress <= 0) {
          charCount++;
          continue;
        }

        // Apply physics curve
        final curveValue = physics == LyricPhysics.slam 
            ? Curves.elasticOut.transform(charProgress) 
            : Curves.easeOutCubic.transform(charProgress);

        // Calculate final character position
        final basePos = wordLayout.charPositions[i];
        final x = basePos.dx + spatialX + driftX;
        final y = basePos.dy + spatialY + driftY + (delta * 60.0); // vertical delta shift

        // Draw character
        final charStyle = style.copyWith(
          color: style.color?.withValues(alpha: curveValue.clamp(0.0, 1.0)),
        );
        
        final tp = TextPainter(
          text: TextSpan(text: char, style: charStyle),
          textDirection: TextDirection.ltr,
        )..layout();

        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(wordRot);
        // Scale arrival effect
        final scale = 1.0 + (1.0 - curveValue) * 0.5;
        canvas.scale(scale, scale);
        
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
        
        charCount++;
      }
    }
  }

  List<_WordLayout> _calculateLayout(List<String> words, Size size, TextStyle style) {
    List<_WordLayout> result = [];
    double currentX = 0;
    double currentY = 0;
    final spaceWidthTp = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final spaceWidth = spaceWidthTp.width;

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final tp = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
      )..layout();

      if (currentX + tp.width > size.width && currentX > 0) {
        currentX = 0;
        currentY += tp.height * 1.2;
      }

      List<Offset> charPositions = [];
      double charX = currentX;
      for (int ci = 0; ci < word.length; ci++) {
        final ctp = TextPainter(
          text: TextSpan(text: word[ci], style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        charPositions.add(Offset(charX + ctp.width / 2, currentY + ctp.height / 2));
        charX += ctp.width;
      }

      result.add(_WordLayout(
        index: i,
        word: word,
        charPositions: charPositions,
      ));
      
      currentX += tp.width + spaceWidth;
    }
    
    // Center the whole block vertically if needed, but for now we keep it relative to top-left of line area
    return result;
  }

  @override
  bool shouldRepaint(ProceduralKineticPainter old) {
    return old.progress != progress || old.time != time || old.delta != delta;
  }
}

class _WordLayout {
  final int index;
  final String word;
  final List<Offset> charPositions;
  _WordLayout({required this.index, required this.word, required this.charPositions});
}
