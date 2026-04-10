import 'package:flutter/material.dart';
import 'procedural_kinetic_painter.dart';

class KineticCanvas extends StatefulWidget {
  final String text;
  final double smoothDelta;
  final TextStyle baseStyle;
  final LyricPhysics physics;
  final int lineIndex;
  final int songHash;
  final bool isActive;
  final bool preroll;

  const KineticCanvas({
    super.key,
    required this.text,
    required this.smoothDelta,
    required this.baseStyle,
    required this.physics,
    required this.lineIndex,
    required this.songHash,
    this.isActive = false,
    this.preroll = false,
  });

  @override
  State<KineticCanvas> createState() => _KineticCanvasState();
}

class _KineticCanvasState extends State<KineticCanvas> with TickerProviderStateMixin {
  late final AnimationController _entry;
  
  // For Brownian motion / Drift animation
  late final AnimationController _timer;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: _entryDuration(widget.physics),
    );
    
    _timer = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    if (widget.smoothDelta.abs() < 0.6 || widget.preroll) {
      _entry.forward();
    }
  }

  Duration _entryDuration(LyricPhysics p) {
    return p == LyricPhysics.slam 
        ? const Duration(milliseconds: 800) 
        : const Duration(milliseconds: 1200);
  }

  @override
  void didUpdateWidget(KineticCanvas old) {
    super.didUpdateWidget(old);
    if (!_entry.isCompleted) {
       if ((old.smoothDelta > 0.4 && widget.smoothDelta <= 0.4) || (!old.preroll && widget.preroll)) {
        _entry.forward();
      }
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: Listenable.merge([_entry, _timer]),
      builder: (context, _) {
        return CustomPaint(
          painter: ProceduralKineticPainter(
            text: widget.text,
            style: widget.baseStyle,
            progress: _entry.value,
            delta: widget.smoothDelta,
            physics: widget.physics,
            lineIndex: widget.lineIndex,
            songHash: widget.songHash,
            time: _timer.value * 10.0, // scale to seconds for noise
          ),
          size: Size.infinite,
        );
      },
    );
  }
}
