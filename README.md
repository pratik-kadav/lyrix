# Lyrix 🎵
**The Kinetic Typography Music Companion for Android**

Lyrix is an ambient, lockscreen-first music companion that intercepts system-wide media playback to display perfectly synced, kinetically animated lyrics. 

Instead of a standard scrolling list, Lyrix operates as a real-time graphic design engine. It treats lyrics as a dynamic 3D poster, specifically designed to run as an immersive lockscreen replacement that aggressively themes itself to your currently playing album art.

## ✨ Features

* **Universal Playback Hook:** Built on Android's `MediaSessionManager`, Lyrix syncs with whatever is playing on your device—Spotify, YouTube Music, Apple Music, or local MP3s. No third-party SDKs required.
* **Algorithmic Typography:** Lyrics aren't just printed; they are designed. The custom Flutter preprocessor wraps, stretches, and stacks multiline text blocks to fill a 90% cinematic safe area, creating a brutalist "poster" effect on the fly.
* **Native Chromesthesia:** Lyrix natively extracts the dominant color from the active album art using Android's `Palette` API. This data is passed to Flutter and clamped via HSL math to guarantee vibrant, legible typography against a void black UI. 
* **Surgical Sync (Fuzzy + Exact Filter):** Utilizes `lrclib.net` with a highly resilient data pipeline. It combines fuzzy text searching with a strict $\pm$3 second duration filter to prevent remixes or live versions from ruining your lyric sync.
* **60FPS Kinetic Engine:** Bypasses standard Flutter offscreen layer bottlenecks. The custom `WordStreamPainter` directly mutates memory addresses for `Paint` objects, ensuring buttery smooth 3D camera panning and "majestic drift" exit transitions even during dense paragraphs.
* **Archived Frequencies:** Once a song's complex visual choreography is calculated, it is cached locally. Subsequent plays load the 3D typography map instantly, completely offline.

## 🏗️ Architecture & Tech Stack

Lyrix is built on a hybrid architecture, prioritizing performance by keeping heavy lifting on the native side and visual rendering on the Flutter side.

* **Frontend:** Flutter (Dart)
* **Backend Hook:** Native Android (Kotlin)
* **APIs:** [LRCLIB](https://lrclib.net/)
* **Local Storage:** `shared_preferences` / JSON Serialization

### The Data Pipeline
1. **Kotlin Service (`LyrixNotificationService`):** Attaches to the active media session via `NotificationListenerService`. Extracts Title, Artist, Duration, exact Playback Position (calculating drift), and Album Art.
2. **Native Color Math:** Generates a Hex color string from the album art Bitmap using `androidx.palette`.
3. **The Bridge:** Broadcasts a lean, 7-part payload over a Flutter `EventChannel`.
4. **Dart Preprocessor:** Fetches `.lrc` files, calculates bounding boxes, assigns 3D camera targets, and prepares the kinetic timeline.
5. **The Canvas:** Flutter's `CustomPainter` renders the active lyric clump while managing smooth camera glides and dynamic text scaling.

## 🚀 Getting Started

### Prerequisites
* Flutter SDK (`^3.8.1` or higher)
* Android Studio / Android SDK (Min SDK 23)

### Installation
1. Clone the repository:
   ```bash
   git clone [https://github.com/yourusername/lyrix.git](https://github.com/yourusername/lyrix.git)

2. Navigate to the project directory:

    Bash
    cd lyrix

3. Install dependencies:

    Bash
    flutter pub get

4. Run the app:

    Bash
    flutter run

Note: On first launch, Lyrix requires Android Notification Access permissions to intercept system media controllers. You will also need to grant Draw Over Other Apps permission to enable the immersive Lockscreen mode.

Roadmap
[x] Native color extraction and HSL contrast clamping

[x] Ruthless duration filtering for accurate lyric fetching

[x] 60FPS memory-mutated custom painting

[ ] iOS Support (via MPMediaItem integration)

[ ] Spotify Canvas-style background ambient video support

[ ] Advanced genre-detection for dynamic font switching



License
This project is licensed under the MIT License - see the LICENSE file for details.