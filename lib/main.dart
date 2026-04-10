import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
// import 'package:palette_generator/palette_generator.dart';
import 'kinetic_styles.dart';
import 'lyric_preprocessor.dart';
import 'word_stream_painter.dart';
import 'services/history_repository.dart';
import 'screens/history_screen.dart';

// --------------------------------------------------------
// MODELS
// --------------------------------------------------------

class LyricsResult {
  final String artist;
  final String track;
  final String? syncedLyrics;
  final String? plainLyrics;
  LyricsResult({required this.artist, required this.track, this.syncedLyrics, this.plainLyrics});
}

class LyricLine {
  final int timestamp;
  final String text;
  LyricLine(this.timestamp, this.text);
}

enum AppGenre { pop, rock, acoustic, electronic, hiphop, unknown }

class GenreTheme {
  final AppGenre genre;
  final Curve enterCurve;
  final int animationDurationMs;
  final KineticStyle kineticStyle;

  GenreTheme({required this.genre, required this.enterCurve, required this.animationDurationMs, required this.kineticStyle});

  static AppGenre parse(String genreString) {
    final s = genreString.toLowerCase();
    if (s.contains('pop')) return AppGenre.pop;
    if (s.contains('rock') || s.contains('metal')) return AppGenre.rock;
    if (s.contains('acoustic') || s.contains('folk') || s.contains('classical') || s.contains('jazz') || s.contains('country')) return AppGenre.acoustic;
    if (s.contains('electronic') || s.contains('dance') || s.contains('house') || s.contains('techno')) return AppGenre.electronic;
    if (s.contains('rap') || s.contains('hip-hop') || s.contains('r&b') || s.contains('hiphop')) return AppGenre.hiphop;
    return AppGenre.unknown;
  }

  static GenreTheme getTheme(AppGenre genre) {
    switch (genre) {
      case AppGenre.pop:
        return GenreTheme(genre: genre, enterCurve: Curves.easeOutCubic, animationDurationMs: 600, kineticStyle: const SlamStyle());
      case AppGenre.rock:
        return GenreTheme(genre: genre, enterCurve: Curves.elasticOut, animationDurationMs: 450, kineticStyle: const SlamStyle());
      case AppGenre.acoustic:
        return GenreTheme(genre: genre, enterCurve: Curves.easeOutSine, animationDurationMs: 900, kineticStyle: const SequentialRollStyle());
      case AppGenre.electronic:
        return GenreTheme(genre: genre, enterCurve: Curves.easeOutBack, animationDurationMs: 400, kineticStyle: const SequentialMatrixStyle());
      case AppGenre.hiphop:
        return GenreTheme(genre: genre, enterCurve: Curves.fastOutSlowIn, animationDurationMs: 500, kineticStyle: const SlamStyle());
      case AppGenre.unknown:
        return GenreTheme(genre: genre, enterCurve: Curves.easeOutCubic, animationDurationMs: 520, kineticStyle: const SlamStyle());
    }
  }

  TextStyle getTextStyle(Color color, double size, {bool isContext = false}) {
    if (isContext) {
      color = Colors.white.withOpacity(0.38);
      size = 15.0;
    }
    final weight = isContext ? FontWeight.w400 : FontWeight.w900;
    final TextStyle base = TextStyle(
      color: color, fontSize: size, fontWeight: weight,
      height: 1.05, letterSpacing: isContext ? 0.4 : -0.5,
    );
    switch (genre) {
      // Pop — Raleway ExtraBold: geometric, punchy, modern
      case AppGenre.pop:
        return GoogleFonts.raleway(textStyle: base.copyWith(fontWeight: isContext ? FontWeight.w500 : FontWeight.w900));
      // Rock — Cinzel: majestic all-caps display serif
      case AppGenre.rock:
        return GoogleFonts.cinzel(textStyle: base.copyWith(fontWeight: isContext ? FontWeight.w500 : FontWeight.w900, letterSpacing: isContext ? 0.4 : 1.2));
      // Acoustic — Playfair Display: elegant editorial serif
      case AppGenre.acoustic:
        return GoogleFonts.playfairDisplay(textStyle: base.copyWith(
            fontStyle: isContext ? FontStyle.normal : FontStyle.italic,
            fontWeight: isContext ? FontWeight.w400 : FontWeight.w700));
      // Electronic — Orbitron: futuristic geometric (closest to Angelos)
      case AppGenre.electronic:
        return GoogleFonts.orbitron(textStyle: base.copyWith(fontWeight: isContext ? FontWeight.w500 : FontWeight.w900));
      // Hip-hop — Bebas Neue: condensed all-caps punch (closest to Milkers/Beach Day energy)
      case AppGenre.hiphop:
        return GoogleFonts.bebasNeue(textStyle: base.copyWith(letterSpacing: isContext ? 0.5 : 2.5));
      // Unknown — Oswald SemiBold: bold condensed, versatile
      case AppGenre.unknown:
        return GoogleFonts.oswald(textStyle: base.copyWith(fontWeight: isContext ? FontWeight.w400 : FontWeight.w700));
    }
  }
}

// --------------------------------------------------------
// REPOSITORY
// --------------------------------------------------------

class LyricsRepository {
  static const _searchUrl = "https://lrclib.net/api/search";

  // 1. Sanitize the string to remove Spotify/Apple Music/JioSaavn junk
  static String _sanitize(String input) {
    String s = input;
    s = s.replaceAll(RegExp(r'\s*\-\s*Recommended for you', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*\-\s*Recommended to you', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*\-\s*Liked', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*\-\s*Track', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*\-\s*Single', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*\-\s*EP', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'•', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\(feat\..*?\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\[feat\..*?\]', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\(ft\..*?\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\- Remaster.*', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\(Remaster.*?\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\(.*?Version.*?\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\[.*?Version.*?\]', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\(.*?Radio Edit.*?\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\- .*?Radio Edit.*', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\[.*?Mix.*?\]', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\(.*?Mix.*?\)', caseSensitive: false), '');
    return s.trim();
  }

  static Future<LyricsResult?> fetchLyrics(String artist, String track, String album, int durationMs) async {
    final ca = _sanitize(artist);
    final ct = _sanitize(track);
    final targetDurationSec = durationMs ~/ 1000;

    // --------------------------------------------------------
    // STEP 1: Surgical Strike (Exact API Get)
    // --------------------------------------------------------
    // LRCLIB's /get requires duration to be within ~2 seconds.
    if (targetDurationSec > 0) {
      try {
        final getUri = Uri.parse("https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(ca)}&track_name=${Uri.encodeComponent(ct)}&album_name=${Uri.encodeComponent(album)}&duration=$targetDurationSec");
        final res = await http.get(getUri).timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final b = jsonDecode(res.body);
          if (b['syncedLyrics'] != null || b['plainLyrics'] != null) {
            return _formatResult(b);
          }
        }
      } catch (e) {
        debugPrint("Strict API match failed: $e");
      }
    }

    // --------------------------------------------------------
    // STEP 2: Fuzzy Search Fallback (With Strict Validation)
    // --------------------------------------------------------
    return await _smartSearch(ct, ca, targetDurationSec);
  }

  static Future<LyricsResult?> _smartSearch(String track, String artist, int targetDuration) async {
    try {
      // Query with both track and artist for high relevance
      final query = "$track $artist";
      final uri = Uri.parse("$_searchUrl?q=${Uri.encodeComponent(query)}");
      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        if (data.isEmpty) return null;

        final targetArtist = artist.toLowerCase();
        final targetTrack = track.toLowerCase();

        Map<String, dynamic>? bestFallbackMatch;

        for (var item in data) {
          final itemArtist = (item['artistName'] ?? '').toString().toLowerCase();
          final itemTrack = (item['trackName'] ?? '').toString().toLowerCase();
          final itemDuration = item['duration'] ?? 0;

          // VALIDATION 1: Artist Match (Partial is okay)
          final isArtistMatch = itemArtist.contains(targetArtist) || targetArtist.contains(itemArtist);

          // VALIDATION 2: Track Match
          // (We check exact equality first, then fallback to partial to prevent remix bleeding)
          final isTrackMatch = itemTrack == targetTrack || itemTrack.contains(targetTrack) || targetTrack.contains(itemTrack);

          if (isArtistMatch && isTrackMatch) {

            // VALIDATION 3: The Ruthless Duration Check (+/- 3 seconds)
            bool isDurationMatch = targetDuration == 0 || (itemDuration - targetDuration).abs() <= 3;

            if (isDurationMatch) {
              // 🎯 PERFECT MATCH!
              if (item['syncedLyrics'] != null) {
                return _formatResult(item); // Instant return if we have sync
              } else if (bestFallbackMatch == null) {
                bestFallbackMatch = item; // Save plain lyrics only if duration matches perfectly
              }
            }
            // 🛑 NOTICE: THE 'ELSE' BLOCK IS GONE.
            // If the duration fails the 3-second check, we drop it immediately. No exceptions.
          }
        }

        // We only return something if it passed the ruthless validation loop
        if (bestFallbackMatch != null) {
          return _formatResult(bestFallbackMatch);
        }
      }
    } catch (e) {
      debugPrint("Search error: $e");
    }

    // Safely trigger the NO LYRIC AVAILABLE UI
    return null;
  }

  static LyricsResult _formatResult(dynamic data) {
    return LyricsResult(
      artist: data['artistName'] ?? '',
      track: data['trackName'] ?? '',
      syncedLyrics: data['syncedLyrics'],
      plainLyrics: data['plainLyrics'],
    );
  }
}

// --------------------------------------------------------
// ALBUM ART + DOMINANT COLOR
// --------------------------------------------------------

class ArtworkService {
  static Future<({String url, String genre})?> fetchArtworkInfo(String artist, String track) async {
    try {
      final q = Uri.encodeComponent("$artist $track");
      final uri = Uri.parse("https://itunes.apple.com/search?term=$q&media=music&limit=1");
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final url = results[0]['artworkUrl100'] as String?;
          final genre = results[0]['primaryGenreName'] as String? ?? "Unknown";
          if (url != null) {
            return (url: url.replaceAll('100x100', '300x300'), genre: genre);
          }
        }
      }
    } catch (e) { debugPrint("Artwork fetch error: $e"); }
    return null;
  }
}

// --------------------------------------------------------
// LRC PARSER
// --------------------------------------------------------

List<LyricLine> parseLrc(String lrc) {
  final lines = <LyricLine>[];
  final re = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
  for (final line in lrc.split('\n')) {
    final m = re.firstMatch(line);
    if (m != null) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final msStr = m.group(3)!;
      final ms = msStr.length == 2 ? int.parse(msStr) * 10 : int.parse(msStr);
      final text = m.group(4)!.trim();
      if (text.isEmpty) continue;
      lines.add(LyricLine((min * 60 * 1000) + (sec * 1000) + ms, text));
    }
  }
  return lines;
}

// --------------------------------------------------------
// NOTIFICATION MANAGER
// --------------------------------------------------------

class NotificationManager {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
      'lyrix_channel', 'Lyrix Updates',
      description: 'Shows live lyrics',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ));
  }

  static Future<void> clear() async => _plugin.cancel(888);
}

// --------------------------------------------------------
// MAIN
// --------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationManager.init();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: LyrixHome(),
  ));
}

// --------------------------------------------------------
// HOME
// --------------------------------------------------------

class LyrixHome extends StatefulWidget {
  const LyrixHome({super.key});
  @override
  State<LyrixHome> createState() => _LyrixHomeState();
}

class _LyrixHomeState extends State<LyrixHome> with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _event = EventChannel('lyrix/nowplaying');
  static const _method = MethodChannel('lyrix/control');

  String _title = "Waiting for music...";
  String _artist = "";
  String _lastFetched = "";
  String _lastFetchedArtist = "";
  String? _artworkUrl;

  List<LyricLine> _lyrics = [];
  String? _plainLyrics;
  int _currentIndex = 0;
  bool _hasSynced = false;
  bool _isPlaying = false;
  bool _isAdActive = false;
  bool _isBackgrounded = false;
  bool _isLockedDevice = false;
  SongChoreography? _choreography;
  bool _isExiting = false;

  bool _isControlsVisible = true;
  Timer? _inactivityTimer;

  double _chaosLevel = 50.0;
  Color _accentColor = Colors.white; // monochrome — pitch black + white typography
  GenreTheme _currentGenreTheme = GenreTheme.getTheme(AppGenre.unknown);

  int _basePosMs = 0;
  DateTime _baseTime = DateTime.now();
  Timer? _ticker;

  late final AnimationController _smoothIndexCtrl;
  late final ValueNotifier<double> _smoothIndex;
  int _prerollIndex = -1; // look-ahead: index of next line to pre-animate

  SideWidgetMode _sideWidgetMode = SideWidgetMode.none;
  double _appBrightness = 1.0; // 1.0 = full bright, 0.0 = pitch black
  Size? _lastProcessedSize;
  String? _lastProcessedSong;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLockState();
    _requestPermissions();
    _startListening();
    _resetInactivityTimer();

    _smoothIndex = ValueNotifier(0.0);
    _smoothIndexCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..addListener(() {
        _smoothIndex.value = _smoothIndexCtrl.value;
      });
  }

  void _resetInactivityTimer() {
    if (!mounted) return;
    setState(() => _isControlsVisible = true);
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isControlsVisible = false);
    });
  }

  Future<void> _checkLockState() async {
    final locked = await _method.invokeMethod('checkLockState') ?? false;
    if (mounted && _isLockedDevice != locked) {
      setState(() => _isLockedDevice = locked);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _inactivityTimer?.cancel();
    _smoothIndexCtrl.dispose();
    _smoothIndex.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkLockState();
    setState(() {
      _isBackgrounded = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    });
  }

  bool _isAd(String artist, String title) {
    final t = title.toLowerCase();
    final a = artist.toLowerCase();
    if (t.contains('advertisement') || t == 'ad') return true;
    if (a.contains('spotify') || a.contains('advertisement')) return true;
    return false;
  }

  void _requestPermissions() {
    FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  void _startListening() {
    _event.receiveBroadcastStream().listen((dynamic event) {
      final parts = (event as String).split('|||');

      // We now expect 7 parts!
      if (parts.length >= 7) {
        final isPlaying = parts[0] == 'true';
        final title = parts[1];
        final artist = parts[2];
        final posMs = int.tryParse(parts[3]) ?? 0;
        final durationMs = int.tryParse(parts[4]) ?? 0;
        final album = parts[5];

        // Parse the Hex Color
        final hexStr = parts[6].replaceFirst('#', '');
        final intHex = int.tryParse(hexStr, radix: 16) ?? 0xFFFFFF;
        Color rawColor = Color(intHex).withAlpha(255);

        // --- THE HSL CONTRAST BUMPER (Anti-Grey / Anti-Dark) ---
        final hsl = HSLColor.fromColor(rawColor);
        final safeColor = hsl
        // Force saturation up (prevents dull greys, min 65% colorfulness)
            .withSaturation(hsl.saturation.clamp(0.65, 1.0))
        // Force lightness up (prevents dark colors blending into the black UI)
            .withLightness(hsl.lightness.clamp(0.60, 0.85))
            .toColor();

        _handleUpdate(isPlaying, title, artist, posMs, durationMs, album, safeColor);
      }
    });

    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isBackgrounded) return;
      if (_hasSynced && _lyrics.isNotEmpty && _isPlaying) _syncLyrics();
    });
  }

  void _handleUpdate(bool playing, String title, String artist, int posMs, int durationMs, String album, Color safeColor) {
    if (title == _lastFetched && posMs > 0) {
      final drift = (posMs - _currentPosMs).abs();
      if (drift > 3000) {
        debugPrint("Sync drift detected: ${drift}ms — re-anchoring");
        setState(() { _basePosMs = posMs; _baseTime = DateTime.now(); });
      }
    }

    setState(() {
      _isPlaying = playing;
      if (playing) {
        _basePosMs = posMs;
        _baseTime = DateTime.now();
      }
      // Apply the color immediately, even on pause/play toggles
      _accentColor = safeColor;
    });

    if (title != _lastFetched || artist != _lastFetchedArtist) {
      final isAdTrack = _isAd(artist, title);

      setState(() {
        _lastFetched = title;
        _lastFetchedArtist = artist;
        _title = title;
        _artist = artist;
        _lyrics = [];
        _plainLyrics = null;
        _currentIndex = 0;
        _hasSynced = false;
        _artworkUrl = null;
        _accentColor = safeColor; // Apply the color for the new track
        _currentGenreTheme = GenreTheme.getTheme(AppGenre.unknown);
        _basePosMs = posMs;
        _baseTime = DateTime.now();
        _isAdActive = isAdTrack;
        _smoothIndex.value = 0.0;
        _smoothIndexCtrl.value = 0.0;
      });

      if (!isAdTrack && title.isNotEmpty) {
        // Log entry so it shows up in history immediately
        HistoryRepository.addOrUpdateHistory(HistoryItem(
            artist: artist, track: title, timestamp: DateTime.now()
        ));

        // Notice: We call _fetchLyrics and _fetchArtwork parallel
        _fetchLyrics(artist, title, album, durationMs);
        _fetchArtwork(artist, title);
      }
    }
  }

  Future<void> _fetchLyrics(String artist, String title, String album, int durationMs) async {
    // 1. Check Archive for existing Signature Signal
    final cached = await HistoryRepository.findItem(artist, title);
    if (cached != null && cached.syncedLyrics != null) {
      final parsed = parseLrc(cached.syncedLyrics!);
      final baseStyle = _currentGenreTheme.getTextStyle(_accentColor, 38.0);
      
      SongChoreography? chro;
      if (cached.serializedChoreography != null && cached.playCount < 5) {
        chro = SongChoreography.dynamicDeserialize(cached.serializedChoreography!, baseStyle);
      }

      setState(() {
        _lyrics = parsed;
        _hasSynced = true;
        _choreography = chro; 
        _basePosMs = _basePosMs; 
      });

      // Update history with latest timestamp and play count increment
      await HistoryRepository.addOrUpdateHistory(cached.copyWith(
        timestamp: DateTime.now(),
        playCount: chro != null ? cached.playCount + 1 : 0, 
      ));
      
      _estimateTempo(parsed);
      return;
    }

    // 2. Refresh signal if no cache exists
    final result = await LyricsRepository.fetchLyrics(artist, title, album, durationMs);
    
    if (result == null) {
      setState(() {
        _lyrics = [];
        _hasSynced = true;
        _choreography = null;
      });
      return;
    }

    if (result.syncedLyrics != null) {
      final parsed = parseLrc(result.syncedLyrics!);
      setState(() { 
        _lyrics = parsed; 
        _hasSynced = true; 
        _choreography = null; 
      });
      _estimateTempo(parsed);

      // Save initial cache (Choreography will be saved by the build loop next)
      await HistoryRepository.addOrUpdateHistory(HistoryItem(
        artist: artist,
        track: title,
        timestamp: DateTime.now(),
        syncedLyrics: result.syncedLyrics,
        plainLyrics: result.plainLyrics,
        genre: _currentGenreTheme.genre.name,
      ));
    } else if (result.plainLyrics != null) {
      setState(() { 
        _plainLyrics = result.plainLyrics; 
        _hasSynced = true; // Still "synced" in the sense that loading is done
        _lyrics = []; 
      });
    } else {
      setState(() {
        _lyrics = [];
        _hasSynced = true;
        _choreography = null;
      });
    }
  }

  /// Derive BPM proxy from average milliseconds between lyric lines.
  /// Maps to animation speed and font weight — our lightweight expression engine.
  void _estimateTempo(List<LyricLine> lines) {
    if (lines.length < 2) return;
    double totalGap = 0;
    for (int i = 1; i < lines.length; i++) {
      totalGap += lines[i].timestamp - lines[i - 1].timestamp;
    }
    final avgIntervalMs = totalGap / (lines.length - 1);
    // Convert avg phrase interval to rough BPM proxy
    final bpm = (60000 / avgIntervalMs).clamp(40.0, 200.0);

    if (!mounted) return;
    setState(() {
      // Tune animation speed from BPM proxy only
      final tempoMs = bpm > 130
          ? 350
          : bpm > 90
              ? 550
              : 850;
      _currentGenreTheme = GenreTheme(
        genre: _currentGenreTheme.genre,
        enterCurve: _currentGenreTheme.enterCurve,
        animationDurationMs: tempoMs,
        kineticStyle: _currentGenreTheme.kineticStyle,
      );
    });
    debugPrint('Tempo: ${bpm.toStringAsFixed(1)} BPM → ${_currentGenreTheme.animationDurationMs}ms');
  }

  Future<void> _fetchArtwork(String artist, String title) async {
    final info = await ArtworkService.fetchArtworkInfo(artist, title);
    if (info == null || !mounted) return;
    
    setState(() {
      _artworkUrl = info.url;
      _currentGenreTheme = GenreTheme.getTheme(GenreTheme.parse(info.genre));
    });
  }

  int get _currentPosMs {
    if (!_isPlaying) return _basePosMs;
    return _basePosMs + DateTime.now().difference(_baseTime).inMilliseconds;
  }

  void _syncLyrics() {
    // +200 ms offset keeps the visual slightly ahead of the vocal.
    final pos = _currentPosMs + 200;
    for (int i = 0; i < _lyrics.length; i++) {
      if (pos >= _lyrics[i].timestamp) {
        if (i == _lyrics.length - 1 || pos < _lyrics[i + 1].timestamp) {

          // ── Active line changed ───────────────────────────────
          if (_currentIndex != i) {
            setState(() => _currentIndex = i);

            // Central Pulse: one AnimationController drives all positions.
            final start = _smoothIndex.value;
            final end   = i.toDouble();
            _smoothIndexCtrl.stop();
            _smoothIndexCtrl.reset();
            _smoothIndexCtrl.animateTo(
              1.0, duration: const Duration(milliseconds: 1100));
            _smoothIndexCtrl.removeListener(_updateSmoothIndex);
            _updateSmoothIndex = () {
              _smoothIndex.value = start +
                  (end - start) *
                      Curves.easeOutQuart
                          .transform(_smoothIndexCtrl.value);
            };
            _smoothIndexCtrl.addListener(_updateSmoothIndex);

            _method.invokeMethod('updateNotification', {
              'title': _title,
              'prev': i > 0 ? _lyrics[i - 1].text : '',
              'curr': _lyrics[i].text,
              'next': i < _lyrics.length - 1 ? _lyrics[i + 1].text : '',
            });
          }

          // ── Look-ahead pre-roll: start next line's character ──
          // streaming 300 ms before its timestamp so text is fully
          // legible exactly on the beat.
          final nextIdx = i + 1;
          if (nextIdx < _lyrics.length) {
            final msToNext = _lyrics[nextIdx].timestamp - pos;
            final shouldPreroll = msToNext > 0 && msToNext <= 300;
            if (shouldPreroll && _prerollIndex != nextIdx) {
              setState(() => _prerollIndex = nextIdx);
            } else if (!shouldPreroll && _prerollIndex == nextIdx) {
              setState(() => _prerollIndex = -1);
            }
          }

          break;
        }
      }
    }
  }

  void Function() _updateSmoothIndex = () {};


  @override
  Widget build(BuildContext context) {
    if (_isLockedDevice) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          setState(() => _isExiting = true);
          await Future.delayed(const Duration(milliseconds: 250));
          await _method.invokeMethod('dropLockScreen');
          if (mounted) setState(() => _isExiting = false);
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: _isExiting ? 0.0 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            color: _isExiting ? Colors.transparent : Colors.black,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: _buildLyricsSection(),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait = constraints.maxHeight > constraints.maxWidth;
        // ONLY hide footer in Landscape if a SideWidget is active
        final hideFooter = !isPortrait && _sideWidgetMode != SideWidgetMode.none;

        return Scaffold(
          backgroundColor: Colors.black, // PURE MONOCHROMATIC VOID
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _resetInactivityTimer,
            child: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(child: _buildLyricsSection()),
                      if (!hideFooter) ...[
                        AnimatedSlide(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOutBack,
                          offset: _isControlsVisible ? Offset.zero : const Offset(0, 1.5),
                          child: _buildHeader(),
                        ),
                        const SizedBox(height: 24),
                      ]
                    ],
                  ),
                  Positioned(
                    top: 16, right: 16,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: _isControlsVisible ? 1.0 : 0.0,
                      child: IconButton(
                        icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.35)),
                        onPressed: () {
                          if (_isControlsVisible) _openSettingsPage(context);
                        },
                      ),
                    ),
                  ),
                  if (!hideFooter)
                    Positioned(
                      bottom: 32, left: 0, right: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 500),
                        opacity: !_isControlsVisible && _title.isNotEmpty ? 1.0 : 0.0,
                        child: Text(
                          "$_title — $_artist",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w400),
                        ),
                      ),
                    ),
                // App-only brightness dimmer overlay
                if (_appBrightness < 1.0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(alpha: 1.0 - _appBrightness),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: const Color(0xFF111111), // MONOCHROME VOID GRAY
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  padding: const EdgeInsets.all(8),
                  splashColor: _accentColor.withValues(alpha: 0.5),
                  highlightColor: _accentColor.withValues(alpha: 0.3),
                  icon: Icon(Icons.arrow_back_ios, color: Colors.white.withValues(alpha: 0.5), size: 28),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _basePosMs -= 500;
                      if (!_isPlaying) _syncLyrics();
                    });
                  },
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _artworkUrl != null
                          ? SpinningArtwork(
                        url: _artworkUrl!,
                        isPlaying: _isPlaying,
                        accentColor: _accentColor,
                      )
                          : Container(
                        key: const ValueKey('placeholder'),
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accentColor.withOpacity(0.1),
                        ),
                        child: Icon(Icons.music_note, color: _accentColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _title,
                              style: const TextStyle(
                                color: Colors.white, fontSize: 14,
                                fontWeight: FontWeight.w600, letterSpacing: -0.3,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _artist,
                              style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 12),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  padding: const EdgeInsets.all(8),
                  splashColor: _accentColor.withValues(alpha: 0.5),
                  highlightColor: _accentColor.withValues(alpha: 0.3),
                  icon: Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.5), size: 28),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _basePosMs += 500;
                      if (!_isPlaying) _syncLyrics();
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSettingsPage(BuildContext context) async {
    if (!context.mounted) return;

    final result = await showDialog(
      context: context,
      builder: (context) => LyrixSettingsDialog(
        initialMode: _sideWidgetMode,
        initialBrightness: _appBrightness,
        onModeChanged: (newMode) {
          setState(() => _sideWidgetMode = newMode);
        },
        onBrightnessChanged: (val) {
          setState(() => _appBrightness = val);
        },
      ),
    );

    if (result != null && result is HistoryItem) {
      _loadSignalFromHistory(result);
    }
  }

  Widget _buildLyricsSection() {
    if (_isAdActive) return const Center(child: Icon(Icons.campaign_outlined, color: Colors.white24, size: 48));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait = constraints.maxHeight > constraints.maxWidth;
        final splitActive = !isPortrait && _sideWidgetMode != SideWidgetMode.none;

        if (isPortrait) {
          // PORTRAIT: Always 100% lyrics, classic centered experience
          return _buildWordStream(constraints.biggest);
        } else {
          // LANDSCAPE: Optional 40/60 Split for Utility
          return Row(
            children: [
              if (splitActive)
                Expanded(
                  flex: 40,
                  child: _buildSideWidget(isPortrait: false),
                ),
              Expanded(
                flex: splitActive ? 60 : 100,
                child: _buildWordStream(constraints.biggest),
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildWordStream(Size areaSize) {
    if (!_hasSynced) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.graphic_eq, color: Colors.white24, size: 32),
            const SizedBox(height: 16),
            Text("FETCHING LYRICS", style: GoogleFonts.spaceGrotesk(color: Colors.white24, fontWeight: FontWeight.w900, letterSpacing: 4.0, fontSize: 12)),
          ],
        ),
      );
    }

    if (_lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.blur_off, color: Colors.white12, size: 64),
            const SizedBox(height: 16),
            Text("NO LYRIC AVAILABLE", style: GoogleFonts.spaceGrotesk(color: Colors.white24, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
          ],
        ),
      );
    }

    // DYNAMIC CHOREOGRAPHY RESOLVER - Performance Optimized
    // Only runs when constraints actually change. 
    final bool needsRegen = _choreography == null || 
                            _lastProcessedSize?.width != areaSize.width || 
                            _lastProcessedSize?.height != areaSize.height ||
                            _lastProcessedSong != _title;

    if (needsRegen && areaSize.width > 10 && areaSize.height > 10) {
      final baseStyle = _currentGenreTheme.getTextStyle(_accentColor, 38.0);
      final chro = LyricPreprocessor.process(
        lines: _lyrics, 
        baseStyle: baseStyle, 
        screenSize: areaSize, 
        songHash: (_artist + _title).hashCode,
        genre: _currentGenreTheme.genre,
      );
      
      _choreography = chro;
      _lastProcessedSize = areaSize;
      _lastProcessedSong = _title;

      // Persist the NEW Signature Path to the Archive
      HistoryRepository.findItem(_artist, _title).then((item) {
        if (item != null) {
          HistoryRepository.addOrUpdateHistory(item.copyWith(
            serializedChoreography: chro.serialize(),
            playCount: 1, // First play of this specific signature
          ));
        }
      });
    }

    if (_choreography == null || _choreography!.words.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.graphic_eq, color: Colors.white12, size: 28),
            const SizedBox(height: 16),
            Text("BUILDING KINETIC ENGINE", style: GoogleFonts.spaceGrotesk(color: Colors.white24, fontWeight: FontWeight.w900, letterSpacing: 4.0, fontSize: 12)),
          ],
        ),
      );
    }

    return WordStreamCanvas(
      choreography: _choreography!,
      basePosMs: _basePosMs,
      baseTime: _baseTime,
      isPlaying: _isPlaying,
      accentColor: _accentColor,
      bpm: _currentGenreTheme.animationDurationMs > 0 ? 60000 / _currentGenreTheme.animationDurationMs : 100,
      genre: _currentGenreTheme.genre,
    );
  }

  Widget _buildSideWidget({bool isPortrait = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        border: Border(
           right: !isPortrait ? BorderSide(color: Colors.white.withOpacity(0.05)) : BorderSide.none,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_sideWidgetMode == SideWidgetMode.clock)
            const Expanded(child: LyrixChrono()),
          if (_sideWidgetMode == SideWidgetMode.banner)
            const Expanded(child: Icon(Icons.music_note, color: Colors.white10, size: 64)),
          
          const SizedBox(height: 24),
          Text(_title.toUpperCase(), 
            textAlign: TextAlign.center,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text(_artist, 
            textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: Colors.white.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }


  void _loadSignalFromHistory(HistoryItem item) async {
    if (item.syncedLyrics == null) return;
    
    final parsed = parseLrc(item.syncedLyrics!);
    final genre = item.genre != null 
        ? AppGenre.values.firstWhere((e) => e.name == item.genre, orElse: () => AppGenre.unknown)
        : AppGenre.unknown;
        
    setState(() {
      _title = item.track;
      _artist = item.artist;
      _lyrics = parsed;
      _hasSynced = true;
      _currentGenreTheme = GenreTheme.getTheme(genre);
      _basePosMs = 0;
      _baseTime = DateTime.now();
      _isPlaying = false; // It's a re-visualization of a signal
      _choreography = null; // Will load serialized in next step if available
    });

    if (item.serializedChoreography != null) {
      final baseStyle = _currentGenreTheme.getTextStyle(_accentColor, 38.0);
      _choreography = SongChoreography.dynamicDeserialize(item.serializedChoreography!, baseStyle);
      setState(() {});
    }
  }
}

enum SideWidgetMode { none, clock, banner }

// --- SETTINGS DIALOG ---
class LyrixSettingsDialog extends StatefulWidget {
  final SideWidgetMode initialMode;
  final double initialBrightness;
  final Function(SideWidgetMode) onModeChanged;
  final Function(double) onBrightnessChanged;

  const LyrixSettingsDialog({
    super.key,
    required this.initialMode,
    required this.initialBrightness,
    required this.onModeChanged,
    required this.onBrightnessChanged,
  });

  @override
  State<LyrixSettingsDialog> createState() => _LyrixSettingsDialogState();
}

class _LyrixSettingsDialogState extends State<LyrixSettingsDialog> {
  late SideWidgetMode _mode;
  late double _brightness;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _brightness = widget.initialBrightness;
  }

  Widget _buildModeBtn(String label, SideWidgetMode mode) {
    final isSelected = _mode == mode;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: InkWell(
          onTap: () {
            setState(() => _mode = mode);
            widget.onModeChanged(mode);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : const Color(0xFF1F1F1F),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(label, 
                style: GoogleFonts.inter(color: isSelected ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A0A0A),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("SETTINGS", style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                IconButton(icon: Icon(Icons.close, color: Colors.white.withOpacity(0.5)), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 24),
            Text("UTILITY WIDGET", style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildModeBtn("OFF", SideWidgetMode.none),
                _buildModeBtn("CLOCK", SideWidgetMode.clock),
                _buildModeBtn("BANNER", SideWidgetMode.banner),
              ],
            ),
            const SizedBox(height: 28),
            // --- BRIGHTNESS SLIDER ---
            Text("BRIGHTNESS", style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1F1F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.brightness_low_rounded, color: Colors.white.withValues(alpha: 0.4), size: 20),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: Colors.white.withValues(alpha: 0.6),
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        trackHeight: 3,
                        overlayColor: Colors.white.withValues(alpha: 0.08),
                        activeTickMarkColor: Colors.white.withValues(alpha: 0.3),
                        inactiveTickMarkColor: Colors.white.withValues(alpha: 0.1),
                        tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
                      ),
                      child: Slider(
                        value: _brightness,
                        min: 0.05,
                        max: 1.0,
                        divisions: 6,
                        label: '${(_brightness * 100).round()}%',
                        onChanged: (val) {
                          HapticFeedback.lightImpact();
                          setState(() => _brightness = val);
                          widget.onBrightnessChanged(val);
                        },
                      ),
                    ),
                  ),
                  Icon(Icons.brightness_high_rounded, color: Colors.white.withValues(alpha: 0.7), size: 20),
                ],
              ),
            ),
            const SizedBox(height: 32),
            InkWell(
              onTap: () async {
                final result = await Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (context) => const ArchivedFrequenciesScreen())
                );
                if (result != null) {
                  Navigator.pop(context, result);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Archived Frequencies", style: GoogleFonts.notoSerif(color: Colors.white, fontSize: 16, fontStyle: FontStyle.italic)),
                    Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.5), size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- MINIMALIST NATIVE CLOCK ---
class LyrixChrono extends StatefulWidget {
  const LyrixChrono({super.key});
  @override State<LyrixChrono> createState() => _LyrixChronoState();
}

class _LyrixChronoState extends State<LyrixChrono> with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  @override void dispose() { _ticker.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(200, 200),
          painter: ChronoPainter(now: DateTime.now()),
        );
      },
    );
  }
}

class ChronoPainter extends CustomPainter {
  final DateTime now;
  ChronoPainter({required this.now});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Outer Circle
    canvas.drawCircle(center, radius, paint);

    // Ticks
    for (int i = 0; i < 60; i++) {
      double angle = (i * 6) * pi / 180;
      double tickLen = (i % 5 == 0) ? 12 : 6;
      final p1 = center + Offset(cos(angle) * (radius - 4), sin(angle) * (radius - 4));
      final p2 = center + Offset(cos(angle) * (radius - 4 - tickLen), sin(angle) * (radius - 4 - tickLen));
      canvas.drawLine(p1, p2, paint..color = Colors.white.withOpacity(i % 5 == 0 ? 0.3 : 0.1));
    }

    // Hands
    final hAngle = (now.hour % 12 + now.minute / 60) * 30 * pi / 180 - pi / 2;
    final mAngle = (now.minute + now.second / 60) * 6 * pi / 180 - pi / 2;
    final sAngle = (now.second + now.millisecond / 1000) * 6 * pi / 180 - pi / 2;

    _drawHand(canvas, center, hAngle, radius * 0.5, 3, Colors.white);
    _drawHand(canvas, center, mAngle, radius * 0.75, 2, Colors.white.withOpacity(0.8));
    _drawHand(canvas, center, sAngle, radius * 0.85, 1, Colors.redAccent.withOpacity(0.8));
    
    // Center point
    canvas.drawCircle(center, 3, Paint()..color = Colors.white);
  }

  void _drawHand(Canvas canvas, Offset center, double angle, double length, double width, Color color) {
    canvas.drawLine(
      center,
      center + Offset(cos(angle) * length, sin(angle) * length),
      Paint()..color = color..strokeWidth = width..strokeCap = StrokeCap.round,
    );
  }

  @override bool shouldRepaint(ChronoPainter old) => true;
}

// Positioned Helper
class Position8 extends StatelessWidget {
  final double? top, left, bottom, right;
  final Widget child;
  const Position8({super.key, this.top, this.left, this.bottom, this.right, required this.child});
  @override Widget build(BuildContext context) => Positioned(top: top, left: left, bottom: bottom, right: right, child: child);
}

// --------------------------------------------------------
// NO LONGER NEEDED: _LyricLineAnimator (Replaced by Global ValueListenableBuilder)
// --------------------------------------------------------

// --------------------------------------------------------
// SPINNING ARTWORK
// --------------------------------------------------------

class SpinningArtwork extends StatefulWidget {
  final String url;
  final bool isPlaying;
  final Color accentColor;
  const SpinningArtwork({super.key, required this.url, required this.isPlaying, required this.accentColor});

  @override
  State<SpinningArtwork> createState() => _SpinningArtworkState();
}

class _SpinningArtworkState extends State<SpinningArtwork> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override void initState() { 
    super.initState(); 
    if (widget.isPlaying) _c.repeat(); 
  }
  
  @override void didUpdateWidget(SpinningArtwork old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !old.isPlaying) _c.repeat();
    else if (!widget.isPlaying && old.isPlaying) _c.stop();
  }
  
  @override void dispose() { _c.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle, 
          boxShadow: [BoxShadow(color: widget.accentColor.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: -2)], 
          image: DecorationImage(image: NetworkImage(widget.url), fit: BoxFit.cover)
        ),
      ),
    );
  }
}

// --------------------------------------------------------
// WORD ANIMATED LYRIC — core piece
// Words fly in from random directions with stagger + spring
// Old words rise up and fade out (handled by Flutter's key system)
// --------------------------------------------------------

