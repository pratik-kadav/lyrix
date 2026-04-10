import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

abstract class KineticStyle {
  const KineticStyle();

  Animate applyEnteringAnimation(
      Animate anim, Duration duration, Duration delay, int wordIndex, int textHash, double chaos);

  Widget applyStateTransformation(
      double delta, int lyricIndex, int textHash, Widget child, double chaos,
      {required Size screen, required double activeLineH});
}

// --------------------------------------------------------
// 2D LAYOUT PLANNER
// --------------------------------------------------------

enum LyricRole { past, active, future }

enum ExitEffect { fade, slide, mist, pop, dissolve }

/// Deterministic signature per lyric line for its "Past" behaviour.
class _PastSignature {
  final Offset targetOffset;
  final double targetRotate;
  final ExitEffect exitEffect;

  _PastSignature({required this.targetOffset, required this.targetRotate, required this.exitEffect});

  static _PastSignature get(int index, int hash, Size screen) {
    final corners = [
      Offset(-screen.width * 0.28, -screen.height * 0.30), // Top Left
      Offset(screen.width * 0.28,  -screen.height * 0.33), // Top Right
      Offset(-screen.width * 0.24, -screen.height * 0.14), // Mid Left
      Offset(screen.width * 0.24,  -screen.height * 0.17), // Mid Right
    ];

    final effects = ExitEffect.values;
    final angles  = [1.5708, -1.5708, 0.7854, -0.7854, 3.1416];

    final cIdx = (index + hash.abs()) % corners.length;
    final eIdx = (index + hash.abs()) % effects.length;
    final aIdx = (index + hash.abs()) % angles.length;

    return _PastSignature(
      targetOffset: corners[cIdx],
      targetRotate: angles[aIdx],
      exitEffect:   effects[eIdx],
    );
  }
}

({double slideX, double slideY, double opacity, double scale, double rotateZ, double blur})
    _layoutPlan(double delta, int lyricIndex, int textHash, Size screen, double activeLineH) {

  final role = delta < 0 ? LyricRole.past
             : delta == 0 ? LyricRole.active
             : LyricRole.future;

  if (role == LyricRole.past) {
    final r = (-delta).clamp(0.0, 4.0);
    final t = r.clamp(0.0, 1.0);

    final sig         = _PastSignature.get(lyricIndex, textHash, screen);
    const targetScale = 0.28;

    final slideX  = sig.targetOffset.dx * pow(t, 0.5);
    final slideY  = sig.targetOffset.dy * t;
    final scale   = 1.0 - t * (1.0 - targetScale);
    final rotT    = ((t - 0.2) / 0.8).clamp(0.0, 1.0);
    final rotateZ = sig.targetRotate * rotT;

    final exitT        = ((r - 1.0) / 2.5).clamp(0.0, 1.0);
    double opacity     = (1.0 - t * 0.75).clamp(0.25, 1.0);
    double blur        = 0.0;
    double currentScale = scale;

    switch (sig.exitEffect) {
      case ExitEffect.mist:
        blur     = exitT * 10.0;
        opacity *= (1.0 - exitT);
        break;
      case ExitEffect.pop:
        currentScale *= (1.0 + exitT * 0.45);
        opacity      *= (1.0 - pow(exitT, 0.5).toDouble());
        break;
      case ExitEffect.dissolve:
        opacity *= (1.0 - exitT);
        blur     = exitT * 4.0;
        break;
      case ExitEffect.slide:
      default:
        opacity *= (1.0 - exitT);
    }

    return (slideX: slideX, slideY: slideY, opacity: opacity,
            scale: currentScale, rotateZ: rotateZ, blur: blur);

  } else if (role == LyricRole.active) {
    return (slideX: 0.0, slideY: 0.0, opacity: 1.0, scale: 1.0, rotateZ: 0.0, blur: 0.0);

  } else {
    final r        = delta.clamp(0.0, 3.5);
    final futureGap = activeLineH * 0.75 + 32;
    final targetY  = (futureGap * r).clamp(0.0, screen.height * 0.45);
    final opacity  = (0.22 * (1.0 - (r - 1.0).clamp(0.0, 1.0))).clamp(0.0, 0.22);
    return (slideX: 0.0, slideY: targetY, opacity: opacity,
            scale: 0.5 - r.clamp(0.0, 1.0) * 0.1, rotateZ: 0.0, blur: 0.0);
  }
}

Widget _applyLayout(double delta, int lyricIndex, int textHash,
    Widget child, Size screen, double activeLineH) {
  final p = _layoutPlan(delta, lyricIndex, textHash, screen, activeLineH);

  Widget content = Opacity(opacity: p.opacity.clamp(0.0, 1.0), child: child);

  if (p.blur > 0.1) {
    content = ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: p.blur, sigmaY: p.blur),
      child: content,
    );
  }

  return Transform(
    alignment: Alignment.center,
    transform: Matrix4.identity()
      ..translate(p.slideX, p.slideY, 0.0)
      ..scale(p.scale, p.scale, 1.0)
      ..rotateZ(p.rotateZ),
    child: content,
  );
}

// --------------------------------------------------------
// LYRIC MOMENT CLASSIFIER
// --------------------------------------------------------
enum _Moment { slam, wipeReveal, flip3D, charStagger, shimmerActive, letterCollapse, gravityDrop, blurFocus, spiralIn, glitchSlice }

_Moment classifyMoment(String text, int lineIndex) {
  final words = text.trim().split(RegExp(r'\s+'));
  final wc    = words.length;
  final hash  = (text.hashCode.abs() + lineIndex) % 10;

  if (wc <= 2)   return _Moment.slam;           // Short punchy lines: Slam
  if (wc >= 10)  return _Moment.charStagger;    // Long lines: char cascade
  if (hash == 0) return _Moment.wipeReveal;
  if (hash == 1) return _Moment.flip3D;
  if (hash == 2) return _Moment.charStagger;
  if (hash == 3) return _Moment.shimmerActive;
  if (hash == 4) return _Moment.letterCollapse;
  if (hash == 5) return _Moment.gravityDrop;
  if (hash == 6) return _Moment.blurFocus;
  if (hash == 7) return _Moment.spiralIn;
  if (hash == 8) return _Moment.glitchSlice;
  return _Moment.slam;
}

// --------------------------------------------------------
// 1. SLAM  (existing — scale punch)
// --------------------------------------------------------
class SlamStyle extends KineticStyle {
  const SlamStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    return anim
        .scale(begin: const Offset(2.8, 2.8), end: const Offset(1.0, 1.0),
               duration: duration, curve: Curves.easeOutExpo, delay: delay)
        .fadeIn(duration: 180.ms, delay: delay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 2. WIPE REVEAL  — text slides in from behind a ClipRect mask
//    Every word is clipped to its own bounding box and slides up from below.
// --------------------------------------------------------
class WipeRevealStyle extends KineticStyle {
  const WipeRevealStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    // Reveal word upward from its own clipped base
    // flutter_animate doesn't have clipRect, so we simulate with slideY + custom clip
    return anim
        .slideY(begin: 0.6, end: 0.0,
                duration: duration,
                curve: Curves.easeOutQuart,
                delay: delay)
        .fadeIn(duration: (duration.inMilliseconds * 0.5).round().ms, delay: delay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 3. FLIP 3D  — rotates in on the X axis (card-flip from top)
// --------------------------------------------------------
class Flip3DStyle extends KineticStyle {
  const Flip3DStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    return anim
        .flipV(
          begin: -0.5,   // starts folded up (-180° in half)
          end: 0.0,
          duration: duration,
          curve: Curves.easeOutBack,
          delay: delay,
        )
        .fadeIn(duration: 200.ms, delay: delay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 4. PER-CHARACTER STAGGER
//    The text is rebuilt character by character (not word by word).
//    This style operates differently: it wraps the WHOLE line, not per-word.
//    applyEnteringAnimation is called per-word, so we use it per-word
//    with a very tight character-scale stagger using delay per letter.
// --------------------------------------------------------
class CharStaggerStyle extends KineticStyle {
  const CharStaggerStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    // Each word drops in from Y=-20px with a per-word stagger
    // Character-level would need a custom widget (see note in guide)
    final staggerDelay = delay + (wordIndex * 35).ms;
    return anim
        .slideY(begin: -0.4, end: 0.0,
                duration: duration, curve: Curves.easeOutCubic, delay: staggerDelay)
        .scale(begin: const Offset(0.85, 0.85), end: const Offset(1.0, 1.0),
               duration: duration, curve: Curves.easeOutBack, delay: staggerDelay)
        .fadeIn(duration: 160.ms, delay: staggerDelay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 5. SHIMMER ACTIVE  — words slide in from random side + shimmer wave
// --------------------------------------------------------
class ShimmerStyle extends KineticStyle {
  const ShimmerStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    final goLeft = (textHash + wordIndex) % 2 == 0;
    return anim
        .slideX(begin: goLeft ? -0.25 : 0.25, end: 0.0,
                duration: duration, curve: Curves.easeOutCubic, delay: delay)
        .fadeIn(duration: 220.ms, delay: delay)
        .shimmer(
          duration: 800.ms,
          delay: delay + duration,
          color: Colors.white.withValues(alpha: 0.7),
        );
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 6. LETTER-SPACING COLLAPSE  — words arrive spaced-out & snap together
//    Flutter_animate doesn't have a letterSpacing tween, so we simulate
//    it by scaling X-only (wider → normal) plus fade-in.
// --------------------------------------------------------
class LetterCollapseStyle extends KineticStyle {
  const LetterCollapseStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    return anim
        .scale(
          begin: const Offset(1.5, 1.0), // Wide X, normal Y
          end:   const Offset(1.0, 1.0),
          duration: duration,
          curve: Curves.easeOutExpo,
          delay: delay,
          alignment: (wordIndex % 2 == 0) ? Alignment.centerLeft : Alignment.centerRight,
        )
        .fadeIn(duration: 150.ms, delay: delay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 7. SEQUENTIAL ROLL  (kept for genre-theme usage)
// --------------------------------------------------------
class SequentialRollStyle extends KineticStyle {
  const SequentialRollStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    return anim
        .slideX(begin: -0.3, end: 0.0, duration: duration,
                curve: Curves.easeOutCubic, delay: delay)
        .fadeIn(duration: 180.ms, delay: delay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 8. SEQUENTIAL MATRIX  (kept for electronic genre)
// --------------------------------------------------------
class SequentialMatrixStyle extends KineticStyle {
  const SequentialMatrixStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    return anim
        .slideX(begin: 0.1, end: 0.0, duration: duration,
                curve: Curves.easeOut, delay: delay)
        .fadeIn(duration: 100.ms, delay: delay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 9. SPLIT  (kept for acoustic genre)
// --------------------------------------------------------
class SplitStyle extends KineticStyle {
  const SplitStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    final halfLen = (textHash.abs() % 5) + 2;
    final isFirst = wordIndex < halfLen;
    return anim
        .slideX(begin: isFirst ? -0.5 : 0.5, end: 0.0,
                duration: duration, curve: Curves.easeOutBack, delay: delay)
        .slideY(begin: isFirst ? -0.15 : 0.15, end: 0.0,
                duration: duration, curve: Curves.easeOutCubic, delay: delay)
        .fadeIn(duration: 200.ms, delay: delay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 10. GRAVITY DROP — words fall from above with a bounce settle
//     Evokes a heavy, physical weight to each word.
// --------------------------------------------------------
class GravityDropStyle extends KineticStyle {
  const GravityDropStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    final staggerDelay = delay + (wordIndex * 50).ms;
    return anim
        .slideY(begin: -1.2, end: 0.0,
                duration: duration, curve: Curves.bounceOut, delay: staggerDelay)
        .fadeIn(duration: 120.ms, delay: staggerDelay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 11. BLUR FOCUS — words start blurred and rack-focus into clarity
//     Cinematic depth-of-field pull.
// --------------------------------------------------------
class BlurFocusStyle extends KineticStyle {
  const BlurFocusStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    return anim
        .blur(begin: const Offset(12, 12), end: Offset.zero,
              duration: duration, curve: Curves.easeOutQuart, delay: delay)
        .scale(begin: const Offset(1.15, 1.15), end: const Offset(1.0, 1.0),
               duration: duration, curve: Curves.easeOutQuart, delay: delay)
        .fadeIn(duration: (duration.inMilliseconds * 0.4).round().ms, delay: delay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 12. SPIRAL IN — words rotate in from offset with a spin
//     Vortex-pull feel, great for dramatic moments.
// --------------------------------------------------------
class SpiralInStyle extends KineticStyle {
  const SpiralInStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    final clockwise = (textHash + wordIndex) % 2 == 0;
    return anim
        .rotate(begin: clockwise ? -0.15 : 0.15, end: 0.0,
                duration: duration, curve: Curves.easeOutBack, delay: delay)
        .scale(begin: const Offset(0.3, 0.3), end: const Offset(1.0, 1.0),
               duration: duration, curve: Curves.easeOutCubic, delay: delay)
        .fadeIn(duration: 180.ms, delay: delay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// 13. GLITCH SLICE — words jitter horizontally with digital artifact feel
//     Electronic, cyberpunk aesthetic. Rapid shake then settle.
// --------------------------------------------------------
class GlitchSliceStyle extends KineticStyle {
  const GlitchSliceStyle();

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) {
    final dir = (wordIndex % 2 == 0) ? 1.0 : -1.0;
    return anim
        .slideX(begin: dir * 0.35, end: 0.0,
                duration: 120.ms, curve: Curves.easeOut, delay: delay)
        .then()
        .slideX(begin: -dir * 0.12, end: 0.0,
                duration: 100.ms, curve: Curves.easeInOut)
        .then()
        .slideX(begin: dir * 0.04, end: 0.0,
                duration: 80.ms, curve: Curves.easeInOut)
        .fadeIn(duration: 80.ms, delay: delay);
  }

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _applyLayout(delta, lyricIndex, textHash, child, screen, activeLineH);
}

// --------------------------------------------------------
// ADAPTIVE WRAPPER — picks the right style per line
// --------------------------------------------------------
class AdaptiveLyricStyle extends KineticStyle {
  final String text;
  final int lineIndex;
  const AdaptiveLyricStyle({required this.text, required this.lineIndex});

  KineticStyle get _inner {
    switch (classifyMoment(text, lineIndex)) {
      case _Moment.slam:           return const SlamStyle();
      case _Moment.wipeReveal:     return const WipeRevealStyle();
      case _Moment.flip3D:         return const Flip3DStyle();
      case _Moment.charStagger:    return const CharStaggerStyle();
      case _Moment.shimmerActive:  return const ShimmerStyle();
      case _Moment.letterCollapse: return const LetterCollapseStyle();
      case _Moment.gravityDrop:    return const GravityDropStyle();
      case _Moment.blurFocus:      return const BlurFocusStyle();
      case _Moment.spiralIn:       return const SpiralInStyle();
      case _Moment.glitchSlice:    return const GlitchSliceStyle();
    }
  }

  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay,
      int wordIndex, int textHash, double chaos) =>
      _inner.applyEnteringAnimation(anim, duration, delay, wordIndex, textHash, chaos);

  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash,
      Widget child, double chaos, {required Size screen, required double activeLineH}) =>
      _inner.applyStateTransformation(delta, lyricIndex, textHash, child, chaos,
          screen: screen, activeLineH: activeLineH);
}

final List<KineticStyle> kineticLibrary = [
  const SlamStyle(),
  const WipeRevealStyle(),
  const Flip3DStyle(),
  const CharStaggerStyle(),
  const ShimmerStyle(),
  const LetterCollapseStyle(),
  const SequentialRollStyle(),
  const SequentialMatrixStyle(),
  const SplitStyle(),
  const GravityDropStyle(),
  const BlurFocusStyle(),
  const SpiralInStyle(),
  const GlitchSliceStyle(),
];
