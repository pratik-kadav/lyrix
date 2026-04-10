import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/history_repository.dart';
import 'signal_detail_screen.dart';

class ArchivedFrequenciesScreen extends StatefulWidget {
  const ArchivedFrequenciesScreen({super.key});

  @override
  State<ArchivedFrequenciesScreen> createState() => _ArchivedFrequenciesScreenState();
}

class _ArchivedFrequenciesScreenState extends State<ArchivedFrequenciesScreen> {
  List<HistoryItem> _allHistory = [];
  List<HistoryItem> _filteredHistory = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _searchController.addListener(_filterHistory);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await HistoryRepository.getHistory();
    setState(() {
      _allHistory = history;
      _filteredHistory = history;
      _isLoading = false;
    });
  }

  void _filterHistory() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredHistory = _allHistory.where((item) {
        return item.track.toLowerCase().contains(query) || 
               item.artist.toLowerCase().contains(query);
      }).toList();
    });
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return "${diff.inMinutes}M AGO";
    if (diff.inHours < 24) return "${diff.inHours}H AGO";
    if (diff.inDays < 7) return "${diff.inDays}D AGO";
    return "${dt.day}/${dt.month}/${dt.year}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // MONOCHROME VOID
      appBar: AppBar(
        title: Text(
          "ARCHIVED SIGNALS",
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
            color: Colors.white,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.spaceGrotesk(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "SEARCH SIGNALS...",
                  hintStyle: GoogleFonts.spaceGrotesk(color: Colors.white.withOpacity(0.2), letterSpacing: 1.0),
                  prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.2)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _filteredHistory.isEmpty
                    ? Center(
                        child: Text(
                          "NO SIGNALS FOUND",
                          style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF222222),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredHistory.length,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemBuilder: (context, index) {
                          final item = _filteredHistory[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Dismissible(
                              key: Key("${item.artist}_${item.track}"),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) {
                                HistoryRepository.deleteItem(item.artist, item.track);
                                _allHistory.removeWhere((i) => i.artist == item.artist && i.track == item.track);
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              ),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context, 
                                    MaterialPageRoute(builder: (context) => SignalDetailScreen(
                                      item: item,
                                      accentColor: Colors.white, // Detail page handles dynamic colors
                                    ))
                                  );
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF080808),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.track.toUpperCase(),
                                              style: GoogleFonts.spaceGrotesk(
                                                color: Colors.white,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: -1.0,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            _formatRelativeTime(item.timestamp),
                                            style: GoogleFonts.spaceGrotesk(
                                              color: Colors.white.withOpacity(0.3),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.artist.toUpperCase(),
                                        style: GoogleFonts.notoSerif(
                                          color: const Color(0xFFE2E2E2).withOpacity(0.7),
                                          fontSize: 14,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      if (item.genre != null) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.05),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            item.genre!.toUpperCase(),
                                            style: GoogleFonts.spaceGrotesk(
                                              color: Colors.white.withOpacity(0.5),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
