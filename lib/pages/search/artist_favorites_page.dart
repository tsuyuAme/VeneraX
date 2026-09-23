import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/pages/aggregated_search_page.dart';
import 'package:venera/pages/search/search_shortcuts.dart';
import 'package:venera/utils/translations.dart';

Map<String, Set<String>> groupArtistShortcuts(List<SearchShortcut> shortcuts) {
  final artists = <String, Set<String>>{};
  for (final shortcut in shortcuts) {
    if (shortcut.kind != SearchShortcutKind.author) continue;
    artists.putIfAbsent(shortcut.value, () => <String>{}).add(
          shortcut.sourceKey,
        );
  }
  return artists;
}

class ArtistFavoritesPage extends StatefulWidget {
  const ArtistFavoritesPage({super.key});

  @override
  State<ArtistFavoritesPage> createState() => _ArtistFavoritesPageState();
}

class _ArtistFavoritesPageState extends State<ArtistFavoritesPage> {
  Map<String, Set<String>> _artists = {};
  String _query = '';

  void _refresh() {
    final artists = groupArtistShortcuts(SearchShortcutManager.instance.all);
    if (mounted) setState(() => _artists = artists);
  }

  @override
  void initState() {
    SearchShortcutManager.instance.addListener(_refresh);
    _refresh();
    super.initState();
  }

  @override
  void dispose() {
    SearchShortcutManager.instance.removeListener(_refresh);
    super.dispose();
  }

  List<MapEntry<String, Set<String>>> get _filtered {
    final q = _query.trim().toLowerCase();
    final entries = _artists.entries.toList();
    if (q.isEmpty) return entries;
    return entries
        .where((e) => e.key.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void _openSearch(String name) {
    context.to(() => AggregatedSearchPage(keyword: name));
  }

  void _copy(String name) {
    Clipboard.setData(ClipboardData(text: name));
    context.showMessage(message: 'Copied'.tl);
  }

  void _remove(String name) {
    showConfirmDialog(
      context: context,
      title: 'Unfavorite author'.tl,
      content: name,
      onConfirm: () {
        SearchShortcutManager.instance.removeAuthorByName(name);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      body: SmoothCustomScrollView(
        slivers: [
          SliverAppbar(title: Text('Favorite authors'.tl)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search'.tl,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  _artists.isEmpty
                      ? 'No favorite artists yet'.tl
                      : 'No results'.tl,
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = list[index];
                  final name = entry.key;
                  final sources = entry.value.join(', ');
                  return GestureDetector(
                    onSecondaryTap: () => _remove(name),
                    child: ListTile(
                      title: Text(name),
                      subtitle: Text(sources),
                      trailing: IconButton(
                        tooltip: 'Copy'.tl,
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () => _copy(name),
                      ),
                      onTap: () => _openSearch(name),
                      onLongPress: () => _remove(name),
                    ),
                  );
                },
                childCount: list.length,
              ),
            ),
        ],
      ),
    );
  }
}
