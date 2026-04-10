import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryItem {
  final String artist;
  final String track;
  final DateTime timestamp;
  
  // Advanced Cache Fields
  final String? syncedLyrics;
  final String? plainLyrics;
  final String? genre;
  final String? serializedChoreography;
  final int playCount; // Tracks how many times this specific signature was played

  HistoryItem({
    required this.artist,
    required this.track,
    required this.timestamp,
    this.syncedLyrics,
    this.plainLyrics,
    this.genre,
    this.serializedChoreography,
    this.playCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'artist': artist,
        'track': track,
        'timestamp': timestamp.toIso8601String(),
        'syncedLyrics': syncedLyrics,
        'plainLyrics': plainLyrics,
        'genre': genre,
        'serializedChoreography': serializedChoreography,
        'playCount': playCount,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        artist: json['artist'] ?? '',
        track: json['track'] ?? '',
        timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
        syncedLyrics: json['syncedLyrics'],
        plainLyrics: json['plainLyrics'],
        genre: json['genre'],
        serializedChoreography: json['serializedChoreography'],
        playCount: json['playCount'] ?? 0,
      );

  HistoryItem copyWith({
    DateTime? timestamp,
    String? syncedLyrics,
    String? plainLyrics,
    String? genre,
    String? serializedChoreography,
    int? playCount,
  }) {
    return HistoryItem(
      artist: artist,
      track: track,
      timestamp: timestamp ?? this.timestamp,
      syncedLyrics: syncedLyrics ?? this.syncedLyrics,
      plainLyrics: plainLyrics ?? this.plainLyrics,
      genre: genre ?? this.genre,
      serializedChoreography: serializedChoreography ?? this.serializedChoreography,
      playCount: playCount ?? this.playCount,
    );
  }
}

class HistoryRepository {
  static const String _key = 'lyrix_history';
  static const int _maxItems = 100;

  static Future<List<HistoryItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key) ?? [];
    return jsonList.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
  }

  static Future<void> addOrUpdateHistory(HistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();

    // DEDUPLICATION: Remove existing entry for this song
    history.removeWhere((i) => 
      i.artist.toLowerCase() == item.artist.toLowerCase() && 
      i.track.toLowerCase() == item.track.toLowerCase()
    );

    // Insert new/updated entry at the top
    history.insert(0, item);

    if (history.length > _maxItems) {
      history.removeRange(_maxItems, history.length);
    }

    final jsonList = history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_key, jsonList);
  }

  static Future<HistoryItem?> findItem(String artist, String track) async {
    final history = await getHistory();
    try {
      return history.firstWhere((i) => 
        i.artist.toLowerCase() == artist.toLowerCase() && 
        i.track.toLowerCase() == track.toLowerCase()
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteItem(String artist, String track) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    history.removeWhere((i) => 
      i.artist.toLowerCase() == artist.toLowerCase() && 
      i.track.toLowerCase() == track.toLowerCase()
    );
    final jsonList = history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_key, jsonList);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
