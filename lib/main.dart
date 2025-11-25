import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const LyrixApp());
}

class LyrixApp extends StatelessWidget {
  const LyrixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lyrix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF050608),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const LyrixDemoScreen(),
    );
  }
}

class LyricLine {
  final Duration time;
  final String text;

  LyricLine(this.time, this.text);
}

class LyrixDemoScreen extends StatefulWidget {
  const LyrixDemoScreen({super.key});

  @override
  State<LyrixDemoScreen> createState() => _LyrixDemoScreenState();
}

class _LyrixDemoScreenState extends State<LyrixDemoScreen> {
  final List<LyricLine> _lyrics = [
    LyricLine(const Duration(seconds: 0),  "Close your eyes, feel the sound,"),
    LyricLine(const Duration(seconds: 4),  "Let the city fade to black,"),
    LyricLine(const Duration(seconds: 8),  "Every heartbeat, every line,"),
    LyricLine(const Duration(seconds: 12), "Singing words we can’t take back,"),
    LyricLine(const Duration(seconds: 16), "This is our late-night echo,"),
    LyricLine(const Duration(seconds: 20), "Floating on a neon sky,"),
    LyricLine(const Duration(seconds: 24), "If the world forgets tomorrow,"),
    LyricLine(const Duration(seconds: 28), "Lyrix keeps the song alive."),
  ];

  Duration _currentPosition = Duration.zero;
  Timer? _timer;
  int _currentIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _startFakePlayback();
  }

  void _startFakePlayback() {
    _timer?.cancel();
    _currentPosition = Duration.zero;
    _currentIndex = 0;

    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        _currentPosition += const Duration(milliseconds: 500);
        _updateCurrentIndex();
      });
    });
  }

  void _updateCurrentIndex() {
    int newIndex = _currentIndex;

    for (int i = 0; i < _lyrics.length; i++) {
      final isLast = i == _lyrics.length - 1;
      final start = _lyrics[i].time;
      final end = isLast ? start + const Duration(seconds: 4) : _lyrics[i + 1].time;

      if (_currentPosition >= start && _currentPosition < end) {
        newIndex = i;
        break;
      }
    }

    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;

      // Smooth scroll to keep current line near center
      _scrollController.animateTo(
        (_currentIndex * 48).toDouble(), // approx height per item
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _restartDemo() {
    _startFakePlayback();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lyrix • Demo'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Song info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF8E2DE2),
                            Color(0xFF4A00E0),
                          ],
                        ),
                      ),
                      child: const Icon(Icons.music_note, size: 32),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Late Night Echo',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Demo Artist • Fake playback',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Lyrics list
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _lyrics.length,
                    itemBuilder: (context, index) {
                      final line = _lyrics[index];
                      final isActive = index == _currentIndex;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        alignment: Alignment.center,
                        child: Opacity(
                          opacity: isActive ? 1 : 0.45,
                          child: Text(
                            line.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isActive ? 20 : 16,
                              fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w400,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _restartDemo,
                    icon: const Icon(Icons.replay),
                    label: const Text('Restart demo'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
