import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart'; // To get AppGenre

enum TransitionType { standard, flip, past, through }
enum FlipDirection { up, down, left, right }

/// Represents a single word's timing, position, and pre-calculated layout.
class WordEvent {
  final String text;
  final int startTimeMs;
  final int durationMs;
  final int clumpId;
  final Offset position;
  final Offset cameraTarget;
  final double cameraRotation;
  final double cameraZoom;
  final TransitionType transitionType;
  final FlipDirection flipDirection;
  final double rotation;
  final double scaleFactor;

  final TextPainter textPainter;
  final TextStyle fontStyle;
  final Paint textPaint; // <--- ADD THIS

  WordEvent({
    required this.text,
    required this.startTimeMs,
    required this.durationMs,
    required this.clumpId,
    required this.position,
    required this.cameraTarget,
    required this.cameraRotation,
    required this.cameraZoom,
    required this.transitionType,
    required this.flipDirection,
    required this.rotation,
    required this.scaleFactor,
    required this.textPainter,
    required this.fontStyle,
    required this.textPaint, // <--- ADD THIS
  });

  // Keep toPackedJson EXACTLY the same. We don't save the paint to JSON.
  Map<String, dynamic> toPackedJson() => {
    't': text, 's': startTimeMs, 'd': durationMs, 'c': clumpId,
    'x': double.parse(position.dx.toStringAsFixed(1)),
    'y': double.parse(position.dy.toStringAsFixed(1)),
  };
}

class SongChoreography {
  final List<WordEvent> words;
  SongChoreography({required this.words});

  String serialize() {
    if (words.isEmpty) return "{}";
    
    // Group by clump to deduplicate camera data
    final Map<String, Map<String, dynamic>> clumpData = {};
    for (var w in words) {
      final key = w.clumpId.toString();
      if (!clumpData.containsKey(key)) {
        clumpData[key] = {
          'tx': double.parse(w.cameraTarget.dx.toStringAsFixed(1)),
          'ty': double.parse(w.cameraTarget.dy.toStringAsFixed(1)),
          'z': double.parse(w.cameraZoom.toStringAsFixed(2)),
          'cr': double.parse(w.cameraRotation.toStringAsFixed(2)),
          'tt': w.transitionType.index,
          'fd': w.flipDirection.index,
          'ff': w.fontStyle.fontFamily,
          'fs': w.fontStyle.fontSize,
          'fw': w.fontStyle.fontWeight?.index,
        };
      }
    }

    final data = {
      'w': words.map((e) => e.toPackedJson()).toList(),
      'c': clumpData,
    };
    return jsonEncode(data);
  }

  static SongChoreography? dynamicDeserialize(String json, TextStyle baseStyle) {
    try {
      final map = jsonDecode(json);
      final List<dynamic> wordsRaw = map['w'];
      final Map<String, dynamic> clumpsRaw = map['c'];
      
      final List<WordEvent> words = [];
      for (var w in wordsRaw) {
        final cId = w['c'] as int;
        final c = clumpsRaw[cId.toString()];
        final wordPaint = Paint()..color = Colors.white;

        final style = GoogleFonts.getFont(c['ff'],
            // We build a fresh TextStyle to completely drop the inherited 'color'
            textStyle: TextStyle(
              fontSize: c['fs'],
              fontWeight: FontWeight.values[c['fw'] as int],
              letterSpacing: baseStyle.letterSpacing,
              height: baseStyle.height,
              foreground: wordPaint,
            )
        );

        final tp = TextPainter(text: TextSpan(text: w['t'], style: style), textDirection: TextDirection.ltr)..layout();

        words.add(WordEvent(
          text: w['t'],
          startTimeMs: w['s'],
          durationMs: w['d'],
          clumpId: cId,
          position: Offset(w['x'], w['y']),
          cameraTarget: Offset(c['tx'], c['ty']),
          cameraZoom: c['z'],
          cameraRotation: c['cr'],
          transitionType: TransitionType.values[c['tt'] as int],
          flipDirection: FlipDirection.values[c['fd'] as int],
          rotation: c['cr'],
          scaleFactor: 1.0,
          textPainter: tp,
          fontStyle: style,
          textPaint: wordPaint,
        ));
      }
      return SongChoreography(words: words);
    } catch (_) {
      return null;
    }
  }
}

class LyricPreprocessor {
  static SongChoreography process({
    required List<dynamic> lines, 
    required TextStyle baseStyle,
    required Size screenSize,
    required int songHash,
    required AppGenre genre,
  }) {
    if (lines.isEmpty) return SongChoreography(words: []);

    final List<WordEvent> wordEvents = [];
    final rand = Random(songHash);
    final isPortrait = screenSize.height > screenSize.width;

    // FONT SELECTION (Aggressive condensed fonts)
    final List<TextStyle Function(TextStyle)> portraitFonts = [
      (s) => GoogleFonts.anton(textStyle: s),
      (s) => GoogleFonts.bebasNeue(textStyle: s),
      (s) => GoogleFonts.teko(textStyle: s),
      (s) => GoogleFonts.oswald(textStyle: s),
    ];
    final List<TextStyle Function(TextStyle)> landscapeFonts = [
      (s) => GoogleFonts.alfaSlabOne(textStyle: s),
      (s) => GoogleFonts.archivoBlack(textStyle: s),
      (s) => GoogleFonts.bungee(textStyle: s),
    ];

    Offset currentSceneCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    double currentAngle = rand.nextDouble() * 2 * pi;

    final double baseFontSize = 80.0;
    for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      final line = lines[lineIdx];
      final nextTs = (lineIdx + 1 < lines.length) ? lines[lineIdx+1].timestamp : line.timestamp + 5000;
      final String lineText = line.text.trim();
      final wordsList = lineText.split(RegExp(r'\s+'));
      if (wordsList.isEmpty || (wordsList.length == 1 && wordsList[0].isEmpty)) continue;

      final double actualDuration = (nextTs - line.timestamp).toDouble();
      
      final FontWeight perLineWeight = wordsList.length <= 2 ? FontWeight.w900 : FontWeight.w800;
      
      final fontPicker = isPortrait ? portraitFonts : landscapeFonts;
      final selectedFont = fontPicker[rand.nextInt(fontPicker.length)];

      final lineStyle = selectedFont(baseStyle.copyWith(
        fontSize: baseFontSize,
        fontWeight: perLineWeight,
        letterSpacing: isPortrait ? -1.5 : -2.5,
      ));

      // CHOREOGRAPHY
      final List<double> possibleRots = [0, pi / 2];
      final double sceneRotation = possibleRots[rand.nextInt(possibleRots.length)];
      final transition = TransitionType.values[rand.nextInt(TransitionType.values.length)];
      final flipDir = FlipDirection.values[rand.nextInt(FlipDirection.values.length)];

      // --- TARGET POSITIONING (75% ARENA) ---
      final double dist = 400.0 + rand.nextDouble() * 300;
      currentAngle += (rand.nextDouble() - 0.5) * 3.5; 
      Offset rawTarget = currentSceneCenter + Offset(cos(currentAngle) * dist, sin(currentAngle) * dist);
      
      final double posSafeW = screenSize.width * 0.75;
      final double posSafeH = screenSize.height * 0.75;
      currentSceneCenter = Offset(
        rawTarget.dx.clamp((screenSize.width - posSafeW)/2, (screenSize.width + posSafeW)/2),
        rawTarget.dy.clamp((screenSize.height - posSafeH)/2, (screenSize.height + posSafeH)/2),
      );

      // --- MULTILINE POSTER CLUMPING (SMART WRAP) ---
      final double maxWrapWidth = screenSize.width * 0.90; // GREEDY WIDTH
      final List<List<TextPainter>> wrappedLines = [[]];
      final List<double> lineRectWidths = [0];

      for (var word in wordsList) {
        // --- INJECT MUTABLE PAINT FOR NEW LYRICS ---
        final wordPaint = Paint()..color = Colors.white;

        // Rebuild the style manually to strip the inherited `color` and inject the `foreground`
        final wordStyle = TextStyle(
          fontFamily: lineStyle.fontFamily,
          fontSize: lineStyle.fontSize,
          fontWeight: lineStyle.fontWeight,
          fontStyle: lineStyle.fontStyle,
          letterSpacing: lineStyle.letterSpacing,
          // height is completely removed to prevent strict bounding-box clipping of Hindi/Marathi matras
          foreground: wordPaint, // Mutable paint, NO color property
        );

        final tp = TextPainter(text: TextSpan(text: word, style: wordStyle), textDirection: TextDirection.ltr)..layout();
        final currentLineW = lineRectWidths.last;
        final spacing = lineStyle.fontSize! * 0.15; // Tight spacing
        
        if (currentLineW + tp.width + spacing > maxWrapWidth && wrappedLines.last.isNotEmpty) {
           wrappedLines.add([tp]);
           lineRectWidths.add(tp.width);
        } else {
           wrappedLines.last.add(tp);
           lineRectWidths[lineRectWidths.length - 1] += tp.width + (wrappedLines.last.length > 1 ? spacing : 0);
        }
      }

      final double maxBlockWidth = lineRectWidths.reduce(max);
      
      // Calculate Justified Scaling per line
      final List<double> lineScales = [];
      final List<double> lineHeights = [];
      double totalBlockHeight = 0.0;

      for (int i = 0; i < wrappedLines.length; i++) {
        double scale = 1.0;
        if (wordsList.length > 2 && wrappedLines.length > 1) {
             // Cap at 1.6 to prevent a lone short word from ballooning over neighbors
             scale = (maxBlockWidth / lineRectWidths[i]).clamp(0.8, 1.6);
        }
        lineScales.add(scale);

        // Use the tallest glyph in the row as the height basis, but keep rows
        // tightly packed like a movie poster — only 5% breathing room.
        // Don't multiply by scale here; the canvas scaleFactor handles visual sizing.
        double tallest = 0.0;
        for (var tp in wrappedLines[i]) {
          if (tp.height > tallest) tallest = tp.height;
        }
        final rowH = tallest * 0.88; // Slightly less than glyph height for that cramped poster feel
        lineHeights.add(rowH);
        totalBlockHeight += rowH;
      }

      // ARENA ENFORCER: Greedy Scaling
      // Target 90% of the safe area for "Full Bleed"
      final double targetSafeW = screenSize.width * 0.90;
      final double targetSafeH = screenSize.height * 0.90;
      
      double fitZoom = 1.0;
      fitZoom = min(targetSafeW / maxBlockWidth, targetSafeH / totalBlockHeight);
      
      // If it's a short shout, let it be MASSIVE
      final double maxZoom = wordsList.length <= 2 ? 4.5 : 2.0;
      fitZoom = fitZoom.clamp(0.2, maxZoom);

      // POSITON WORDS IN CLUMP
      double currentY = -(totalBlockHeight / 2);
      int absoluteWordIdx = 0;
      
      for (int i = 0; i < wrappedLines.length; i++) {
        final currentLine = wrappedLines[i];
        final currentLineW = lineRectWidths[i];
        final lineScale = lineScales[i];
        
        // Center the line exactly if it didn't stretch fully due to clamp
        double currentX = -(currentLineW * lineScale) / 2;
        final rowH = lineHeights[i];
        
        for (var tp in currentLine) {
          final double wordStartRatio = absoluteWordIdx / wordsList.length;
          
          final scaledWordWidth = tp.width * lineScale;
          final Offset localPos = Offset(currentX + scaledWordWidth / 2, currentY + rowH / 2);
          final double cosR = cos(sceneRotation); final double sinR = sin(sceneRotation);
          final Offset worldPos = currentSceneCenter + Offset(localPos.dx * cosR - localPos.dy * sinR, localPos.dx * sinR + localPos.dy * cosR);

          wordEvents.add(WordEvent(
            text: wordsList[absoluteWordIdx],
            startTimeMs: line.timestamp + (wordStartRatio * actualDuration).toInt(),
            durationMs: actualDuration.toInt() + 100,
            clumpId: lineIdx,
            position: worldPos,
            cameraTarget: currentSceneCenter,
            cameraRotation: sceneRotation,
            cameraZoom: fitZoom,
            transitionType: transition,
            flipDirection: flipDir,
            rotation: sceneRotation,
            scaleFactor: lineScale,
            textPainter: tp,
            fontStyle: tp.text!.style!,
            textPaint: tp.text!.style!.foreground!, // <--- EXTRACT AND ATTACH
          ));
          currentX += scaledWordWidth + ((baseFontSize * 0.15) * lineScale);
          absoluteWordIdx++;
        }
        currentY += rowH;
      }
    }
    return SongChoreography(words: wordEvents);
  }
}
