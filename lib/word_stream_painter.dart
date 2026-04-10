import 'dart:math';
import 'package:flutter/material.dart';
import 'lyric_preprocessor.dart';
import 'main.dart'; // To get AppGenre

class WordStreamPainter extends CustomPainter {
  final List<WordEvent> words;
  final int currentPosMs;
  final Offset cameraPos; 
  final double cameraRotation;
  final double cameraZoom;
  final int? exitingClumpId;
  final int? targetClumpId;
  final double transitionT;
  final Color accentColor;
  final AppGenre genre;

  WordStreamPainter({
    required this.words,
    required this.currentPosMs,
    required this.cameraPos,
    required this.cameraRotation,
    required this.cameraZoom,
    this.exitingClumpId,
    this.targetClumpId,
    required this.transitionT,
    required this.accentColor,
    required this.genre,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (words.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    
    // 1. GLOBAL CAMERA
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.001) // Perspective
      ..translate(center.dx, center.dy)
      ..scale(cameraZoom)
      ..rotateZ(-cameraRotation)
      ..translate(-cameraPos.dx, -cameraPos.dy);

    canvas.save();
    canvas.transform(matrix.storage);

    // Filter windows for performance
    final windowStart = currentPosMs - 5000;
    final windowEnd   = currentPosMs + 10000;

    for (var word in words) {
      final bool isExiting = word.clumpId == exitingClumpId;
      final bool isActiveTarget = word.clumpId == targetClumpId;
      
      if (!isExiting && !isActiveTarget) {
        if (word.startTimeMs < windowStart || word.startTimeMs > windowEnd) continue;
      }

      double opacity = 0.0;
      Matrix4 localMatrix = Matrix4.identity();

      if (isExiting) {
        if (transitionT >= 1.0) {
          opacity = 0.0; // Strictly unmount
        } else {
          // 1. Instant Fallback Fade:
          // Instead of lingering, they fade to 0 in a smooth instant.
          final fadeT = (transitionT * 3.5).clamp(0.0, 1.0);
          opacity = 1.0 - fadeT;

          // 2. Smooth Drop-Back:
          // Move the text downwards slightly instead of floating up.
          final driftY = (transitionT * 60.0);
          localMatrix.translate(0.0, driftY);

          // 3. The Cinematic Compression:
          // Shrink down slightly to 'fall backwards' away from the camera.
          final shrinkScale = 1.0 - (transitionT * 0.15);
          localMatrix.scale(shrinkScale);

          // (Optional: Notice we completely removed the rotateX/rotateY flip logic)
        }
      } else if (isActiveTarget) {
        // --- ARRRIVAL SNAP (ENTRY) + CINEMATIC PUSH ---
        opacity = (transitionT * 1.5).clamp(0.0, 1.0);
        
        // Entry transform
        double entryScale = 1.0;
        if (transitionT < 1.0) {
          if (word.transitionType == TransitionType.through) {
            entryScale = 0.2 + (transitionT * 0.8);
          } else if (word.transitionType == TransitionType.past) {
            entryScale = 1.8 - (transitionT * 0.8);
          }
        }
        
        // Cinematic Push slowly triggers after entry or during
        final wordProgress = ((currentPosMs - word.startTimeMs) / word.durationMs).clamp(0.0, 1.0);
        // Constrain cinematic growth to max 8% to adhere to the 90% strict safe-area bound
        final pushScale = 1.0 + (wordProgress * 0.08).clamp(0.0, 0.08);
        
        localMatrix.scale(entryScale * pushScale);
      }

      if (opacity <= 0.005) continue;

      canvas.save();
      // 1. Move to the clump's focal point for perfect 3D rotations
      canvas.translate(word.cameraTarget.dx, word.cameraTarget.dy);
      canvas.transform(localMatrix.storage);

      // 2. Move to the word's exact local position
      final relativePos = word.position - word.cameraTarget;
      canvas.translate(relativePos.dx, relativePos.dy);

      // 3. Apply the final graphic adjustments
      canvas.rotate(word.rotation);
      canvas.scale(word.scaleFactor);

      // --- THE ROBUST TINT AND OPACITY FIX ---
      // Since Flutter 3 cached Paragraphs are strictly immutable, we use an extremely fast localized
      // bounded saveLayer with BlendMode.srcIn to force the color tint and alpha.
      // We explicitly inflate the bounding rect by 40% to protect Hindi/Marathi matras from getting clipped
      // by the tightly estimated TextPainter bounding box values.
      final rect = Rect.fromCenter(
          center: Offset.zero, 
          width: word.textPainter.width * 1.4, 
          height: word.textPainter.height * 1.4
      );
      final layerPaint = Paint()..colorFilter = ColorFilter.mode(accentColor.withValues(alpha: opacity), BlendMode.srcIn);
      canvas.saveLayer(rect, layerPaint);

      // 4. Paint freely to the temporary layer
      word.textPainter.paint(canvas, Offset(-word.textPainter.width / 2, -word.textPainter.height / 2));
      
      canvas.restore(); // Blends the saveLayer with the srcIn color back to the main canvas

      canvas.restore(); // Restore Camera & Translate for the next word
    }

    canvas.restore(); // Camera
  }

  @override
  bool shouldRepaint(WordStreamPainter old) => true; 
}

class WordStreamCanvas extends StatefulWidget {
  final SongChoreography choreography;
  final int basePosMs;
  final DateTime baseTime;
  final bool isPlaying;
  final Color accentColor;
  final double bpm;
  final AppGenre genre;

  const WordStreamCanvas({
    super.key,
    required this.choreography,
    required this.basePosMs,
    required this.baseTime,
    required this.isPlaying,
    required this.accentColor,
    required this.bpm,
    required this.genre,
  });

  @override
  State<WordStreamCanvas> createState() => _WordStreamCanvasState();
}

class _WordStreamCanvasState extends State<WordStreamCanvas> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  Offset _currentCameraPos = Offset.zero;
  double _currentCameraRot = 0.0;
  double _currentCameraZoom = 1.0;

  int _targetClumpId = -1;
  int? _lastClumpId;
  double _transitionT = 1.0; 

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    if (widget.choreography.words.isNotEmpty) {
      final start = widget.choreography.words.first;
      _currentCameraPos = start.cameraTarget;
      _currentCameraRot = start.cameraRotation;
      _currentCameraZoom = start.cameraZoom;
    }
  }

  @override
  void dispose() { _ticker.dispose(); super.dispose(); }

  int _lastTickMs = 0;

  int _calculateCurrentPosMs() {
    if (!widget.isPlaying) return widget.basePosMs;
    return widget.basePosMs + DateTime.now().difference(widget.baseTime).inMilliseconds;
  }

  double _lerpAngle(double a, double b, double t) {
    double diff = (b - a) % (2 * pi);
    if (diff > pi) diff -= 2 * pi;
    if (diff < -pi) diff += 2 * pi;
    return a + diff * t;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        final currentPosMs = _calculateCurrentPosMs();
        
        // Time-based Delta Calculation
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_lastTickMs == 0) _lastTickMs = now;
        double dt = (now - _lastTickMs) / 1000.0;
        if (dt > 0.05) dt = 0.05; // Cap massive delta spikes
        _lastTickMs = now;

        WordEvent target = widget.choreography.words.last;
        for (var word in widget.choreography.words) {
          if (currentPosMs >= word.startTimeMs) { target = word; } else { break; }
        }

        if (target.clumpId != _targetClumpId) {
          _lastClumpId = _targetClumpId != -1 ? _targetClumpId : null;
          _targetClumpId = target.clumpId;
          _transitionT = 0.0;
        }

        // SMOOTH TRANSITION ENGINE: Fluid, time-based interpolation
        if (_transitionT < 1.0) {
          _transitionT = (_transitionT + (dt / 0.85)).clamp(0.0, 1.0); // 850ms duration
        }

        // FLUID CAMERA: Frame-rate independent gliding
        final double lerpFactor = (1.0 - pow(0.01, dt)).toDouble(); // Smooth exponential glide
        _currentCameraPos = Offset.lerp(_currentCameraPos, target.cameraTarget, lerpFactor)!;
        _currentCameraRot = _lerpAngle(_currentCameraRot, target.cameraRotation, lerpFactor);
        _currentCameraZoom = _currentCameraZoom + (target.cameraZoom - _currentCameraZoom) * lerpFactor;

        final easeT = Curves.fastOutSlowIn.transform(_transitionT);

        // Focal Breathing
        final breathTime = DateTime.now().millisecondsSinceEpoch / 2000.0;
        final focalDriftZoom = 1.0 + (sin(breathTime) * 0.05);

        return CustomPaint(
          size: Size.infinite,
          painter: WordStreamPainter(
            words: widget.choreography.words,
            currentPosMs: currentPosMs,
            cameraPos: _currentCameraPos,
            cameraRotation: _currentCameraRot,
            cameraZoom: _currentCameraZoom * focalDriftZoom,
            exitingClumpId: _lastClumpId,
            targetClumpId: _targetClumpId,
            transitionT: easeT,
            accentColor: widget.accentColor,
            genre: widget.genre,
          ),
        );
      },
    );
  }
}
