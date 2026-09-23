
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/search/search_shortcuts.dart';
import 'package:venera/utils/translations.dart';

/// Search favorited authors and merge results into one list.
///
/// EH has no OR across artists in one query, so we search per-author with
/// limited concurrency and de-dupe by source+id.
class ArtistBatchSearchPage extends StatefulWidget {
  const ArtistBatchSearchPage({
    super.key,
    required this.artists,
    required this.sources,
  });

  final List<String> artists;
  final List<ComicSource> sources;

  @override
  State<ArtistBatchSearchPage> createState() => _ArtistBatchSearchPageState();
}

class _ArtistBatchSearchPageState extends State<ArtistBatchSearchPage> {
  Future<Res<List<Comic>>> _loadPage(int page) async {
    if (widget.artists.isEmpty) {
      return const Res([]);
    }
    if (widget.sources.isEmpty) {
      return Res.error('No Search Sources'.tl);
    }

    final seen = <String>{};
    final out = <Comic>[];
    final errors = <String>[];

    const concurrency = 4;
    var index = 0;
    final tasks = <({ComicSource source, String artist})>[];
    for (final artist in widget.artists) {
      for (final source in widget.sources) {
        tasks.add((source: source, artist: artist));
      }
    }

    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= tasks.length) return;
        final t = tasks[i];
        final data = t.source.searchPageData;
        if (data == null) continue;
        final options =
            (data.searchOptions ?? []).map((e) => e.defaultValue).toList();
        try {
          late Res<List<Comic>> res;
          if (data.loadPage != null) {
            res = await data.loadPage!(t.artist, page, options);
          } else if (data.loadNext != null) {
            if (page != 1) continue;
            res = await data.loadNext!(t.artist, null, options);
          } else {
            continue;
          }
          if (res.error) {
            if (res.errorMessage != null) {
              errors.add('${t.source.name}: ${res.errorMessage}');
            }
            continue;
          }
          for (final c in res.data ?? const <Comic>[]) {
            final key = '${c.sourceKey}\u0000${c.id}';
            if (seen.add(key)) out.add(c);
          }
        } catch (e) {
          errors.add('${t.source.name}: $e');
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    if (out.isEmpty && errors.isNotEmpty) {
      return Res.error(errors.first);
    }
    return Res(out);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = '@n authors · @s sources'
        .tl
        .replaceAll('@n', '${widget.artists.length}')
        .replaceAll('@s', '${widget.sources.length}');

    // Use a normal Appbar + body. Do NOT pass SliverAppbar as ComicList
    // leadingSliver: while loading, ComicList puts leading into a Column
    // (expects RenderBox) and crashes with:
    // _RenderSliverPinnedPersistentHeaderForWidgets is not a subtype of RenderBox.
    return Scaffold(
      appBar: Appbar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Search all authors'.tl),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: ComicList(
        loadPage: _loadPage,
        scrollbarTopPadding: context.padding.top + 56,
      ),
    );
  }
}

List<ComicSource> _searchableSources() {
  final all = ComicSource.all()
      .where((e) => e.searchPageData != null)
      .toList();
  final settings = appdata.settings['searchSources'];
  if (settings is! List || settings.isEmpty) return all;
  final keys = settings.whereType<String>().toSet();
  final filtered = all.where((s) => keys.contains(s.key)).toList();
  return filtered.isEmpty ? all : filtered;
}

/// Show source checklist (none selected by default), then open batch search.
Future<void> openArtistBatchSearch(BuildContext context) async {
  final names = <String>{};
  for (final s in SearchShortcutManager.instance.all) {
    if (s.isAuthor) names.add(s.value);
  }
  if (names.isEmpty) {
    context.showMessage(message: 'No favorite artists yet'.tl);
    return;
  }

  final candidates = _searchableSources();
  if (candidates.isEmpty) {
    context.showMessage(message: 'No Search Sources'.tl);
    return;
  }

  final selected = <String>{};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return ContentDialog(
            title: 'Select sources'.tl,
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pick sources to search. None are selected by default.'.tl,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    for (final s in candidates)
                      CheckboxListTile(
                        dense: true,
                        value: selected.contains(s.key),
                        title: Text(s.name),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              selected.add(s.key);
                            } else {
                              selected.remove(s.key);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              Button.text(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel'.tl),
              ),
              Button.filled(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Confirm'.tl),
              ),
            ],
          );
        },
      );
    },
  );

  if (ok != true || !context.mounted) return;
  if (selected.isEmpty) {
    context.showMessage(message: 'Select at least one source'.tl);
    return;
  }

  final sources =
      candidates.where((s) => selected.contains(s.key)).toList(growable: false);
  context.to(
    () => ArtistBatchSearchPage(
      artists: names.toList(),
      sources: sources,
    ),
  );
}
