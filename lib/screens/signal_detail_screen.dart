import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/history_repository.dart';
import '../lyric_preprocessor.dart';
import '../word_stream_painter.dart';
import '../main.dart'; // To get AppGenre

class SignalDetailScreen extends StatelessWidget {
  final HistoryItem item;
  final Color accentColor;

  const SignalDetailScreen({
    super.key, 
    required this.item,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final parsedLyrics = parseLrc(item.syncedLyrics ?? "");
    final genre = item.genre != null 
        ? AppGenre.values.firstWhere((e) => e.name == item.genre, orElse: () => AppGenre.unknown)
        : AppGenre.unknown;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("SIGNAL ARCHIVE", style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Metadata Header
            Text(item.track.toUpperCase(), style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -2.0, height: 1.0)),
            const SizedBox(height: 8),
            Text(item.artist.toUpperCase(), style: GoogleFonts.notoSerif(color: Colors.white.withOpacity(0.5), fontSize: 18, fontStyle: FontStyle.italic)),
            const SizedBox(height: 48),

            // Word Art Snapshot
            Text("SIGNATURE SNAPSHOT", style: GoogleFonts.spaceGrotesk(color: Colors.white.withOpacity(0.3), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
            const SizedBox(height: 16),
            Container(
              height: 240,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: item.serializedChoreography != null
                    ? _buildSnapshot(context, item, genre)
                    : const Center(child: Icon(Icons.blur_on, color: Colors.white10, size: 48)),
              ),
            ),
            const SizedBox(height: 48),

            // Lyric Timeline
            Text("LYRIC TIMELINE", style: GoogleFonts.spaceGrotesk(color: Colors.white.withOpacity(0.3), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
            const SizedBox(height: 24),
            ...parsedLyrics.map((line) => Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatMs(line.timestamp),
                    style: GoogleFonts.spaceGrotesk(color: accentColor.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      line.text.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.2),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshot(BuildContext context, HistoryItem item, AppGenre genre) {
    // Generate a static representation using the painter
    final baseStyle = GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 38.0, fontWeight: FontWeight.w900);
    final chro = SongChoreography.dynamicDeserialize(item.serializedChoreography!, baseStyle);
    
    if (chro == null || chro.words.isEmpty) {
      return const Center(child: Icon(Icons.blur_on, color: Colors.white10, size: 48));
    }

    // Pick the most central word event to show
    return CustomPaint(
      painter: WordStreamPainter(
        words: chro.words,
        currentPosMs: chro.words[chro.words.length ~/ 2].startTimeMs,
        cameraPos: chro.words[chro.words.length ~/ 2].position,
        cameraRotation: 0,
        cameraZoom: 1.0,
        transitionT: 1.0,
        accentColor: accentColor,
        genre: genre,
      ),
    );
  }

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    return "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  }
}
