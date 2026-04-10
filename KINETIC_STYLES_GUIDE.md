# Extensibility Guide: Cotodama Kinetic Styles

Welcome to the `KineticStyle` engine! 
This guide documents how to infinitely expand the randomness and aesthetic variety of the lyric flow by adding new physics profiles.

## Architecture Concept

Traditional karaoke simply scrolls linearly. Our engine mathematically treats every line of a lyric independently, mapping it across 3 lifecycle states (Past, Active, Future) and shifting it across physical space.

To prevent spaghetti code, **all physical rendering math is completely decoupled from the UI widgets** into the `lib/kinetic_styles.dart` file.

The engine relies on two distinct phases, perfectly synchronized:
1. **Master Delta Engine (`applyStateTransformation`)**: Responsible for sweeping a paragraph gracefully from the future queue layout into the active focus point, and then into the background. (Controlled via `delta`).
2. **Inner Stagger Engine (`applyEnteringAnimation`)**: Responsible for localized "impact" effects on individual words (color flashes, shimmers, rotations). This happens *exactly sequentially* as the lyrics arrive at `delta = 0`.

---

## Tutorial: How to Add a New Style

### Step 1: Create the Subclass
Open `lib/kinetic_styles.dart` and define a new class extending `KineticStyle`:

```dart
class NeonPulseStyle extends KineticStyle {
  const NeonPulseStyle();

  // Code to follow in steps 2 and 3...
}
```

### Step 2: Define Word-by-Word Impact (`applyEnteringAnimation`)
This method intercepts the `flutter_animate` chain.
> ⚠️ **RULE**: DO NOT apply massive `slideX`, `slideY`, or scale transitions here! This clashes with the Master Delta Engine leading to jittery jumps. Keep this isolated to word-by-word aesthetic impacts (tint, shimmer, soft scale bounces).

```dart
  @override
  Animate applyEnteringAnimation(Animate anim, Duration duration, Duration delay, int wordIndex, int textHash) {
    return anim
      // A quick flash of color and a soft, resilient scale pop for each word
      .scale(begin: const Offset(1.3, 1.3), end: const Offset(1.0, 1.0), duration: 400.ms, delay: delay, curve: Curves.elasticOut)
      .tint(color: Colors.cyanAccent.withOpacity(0.8), duration: 200.ms, delay: delay)
      .then()
      .tint(color: Colors.transparent, duration: 400.ms);
  }
```

### Step 3: Define Spacial Matrix Mapping (`applyStateTransformation`)
This is the master coordinate engine. You receive `delta` (the distance in lines from the active timestamp).
- `delta > 0`: The phrase hasn't been sung yet. Keep it small, softly blurred, off in the distance.
- `delta < 0`: The phrase was just sung. Sweep it aggressively away.

```dart
  @override
  Widget applyStateTransformation(double delta, int lyricIndex, int textHash, Widget child) {
    // 1. Always inherit the Safe Space canvas anchor to break the center!
    final anchor = _calculateCanvasAnchor(textHash);
    double slideX = anchor.dx;
    double slideY = anchor.dy;
    double opacity = 1.0;
    double scale = 1.0;

    if (delta < 0) { // FAST PAST RETREAT
      final pastRatio = -delta;
      slideY += pastRatio * 150.0; // drops down violently!
      opacity = (1.0 - (pastRatio * 2.0)).clamp(0.0, 1.0);
    } else if (delta > 0) { // DISTANT FUTURE QUEUE
      final futureRatio = delta;
      slideY += futureRatio * -80.0; // Wait high up in the sky
      scale = 0.6; // Small in the distance
      opacity = (0.2).clamp(0.0, 1.0); // Faintly visible
    }

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..translate(slideX, slideY, 0.0)..scale(scale, scale, 1.0),
      child: Opacity(opacity: opacity, child: child),
    );
  }
```

### Step 4: Inject into the Library!
Scroll to the bottom of `lib/kinetic_styles.dart` and append your new class to the `kineticLibrary` array:

```dart
final List<KineticStyle> kineticLibrary = const [
  GhostDissolveStyle(),
  NotebookPageStyle(),
  SlideDropStyle(),
  CinematicZoomStyle(),
  NeonPulseStyle(), // Your new masterpiece!
];
```
The hashed math engine will immediately mathematically ingest it and randomize it into the song layout completely organically!
