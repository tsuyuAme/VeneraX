import 'dart:async';

import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/pages/search/search_shortcuts.dart';
import 'package:venera/utils/translations.dart';

/// Search every favorited author once and merge results into a single list
/// (similar to JHentai "followed tags" combined query).
///
/// E-Hentai does not support OR across artists in one `f_search`, so we issue
/// one search per author (with limited concurrency) and de-dupe by source+id.
class ArtistBatchSearchPage extends StatefulWidget {
  const ArtistBatchSearchPage({super.key, this.artists});

  /// When null, reads current [SearchShortcutManager] author names.
  final List<String>? artists;

  @override
  State<ArtistBatchSearchPage> createState() => _ArtistBatchSearchPageState();
}

class _ArtistBatchSearchPageState extends State<ArtistBatchSearchPage> {
  late final List<String> _artists;
  late final List<ComicSource> _sources;

  @override
  void initState() {
    super.initState();
    if (widget.artists != null && widget.artists!.isNotEmpty) {
      _artists = widget.artists!
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      final names = <String>{};
      for (final s in SearchShortcutManager.instance.all) {
        if (s.isAuthor) names.add(s.value);
      }
      _artists = names.toList();
    }

    final all = ComicSource.all()
        .where((e) => e.searchPageData != null)
        .map((e) => e.key)
        .toSet();
    final settings = appdata.settings['searchSources'];
    final keys = <String>[];
    if (settings is List) {
      for (final s in settings) {
        if (s is String && all.contains(s)) keys.add(s);
      }
    }
    if (keys.isEmpty) {
      keys.addAll(all);
    }
    _sources = keys.map((k) => ComicSource.find(k)!).toList();
  }

  /// Load [page] for every author × every search source, merge unique comics.
  Future<Res<List<Comic>>> _loadPage(int page) async {
    if (_artists.isEmpty) {
      return const Res([]);
    }
    if (_sources.isEmpty) {
      return Res.error('No Search Sources'.tl);
    }

    final seen = <String>{};
    final out = <Comic>[];
    final errors = <String>[];

    // Cap parallel requests so we do not flood EH / proxy.
    const concurrency = 4;
    var index = 0;
    final tasks = <({ComicSource source, String artist})>[];
    for (final artist in _artists) {
      for (final source in _sources) {
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
          Res<List<Comic>> res;
          if (data.loadPage != null) {
            res = await data.loadPage!(t.artist, page, options);
          } else if (data.loadNext != null) {
            // loadNext sources: only first page is meaningful for batch.
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
            if (seen.add(key)) {
              out.add(c);
            }
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
    final subtitle = _artists.isEmpty
        ? 'No favorite artists yet'.tl
        : '@n authors · @s sources'
            .tl
            .replaceAll('@n', '${_artists.length}')
            .replaceAll('@s', '${_sources.length}');

    return Scaffold(
      body: ComicList(
        leadingSliver: SliverAppbar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Search all authors'.tl),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        loadPage: _artists.isEmpty ? null : _loadPage,
        errorLeading: SliverAppbar(title: Text('Search all authors'.tl)),
        scrollbarTopPadding: context.padding.top + 56,
      ),
    );
  }
}

/// Open batch search for all current favorited authors.
void openArtistBatchSearch(BuildContext context) {
  final names = <String>{};
  for (final s in SearchShortcutManager.instance.all) {
    if (s.isAuthor) names.add(s.value);
  }
  if (names.isEmpty) {
    context.showMessage(message: 'No favorite artists yet'.tl);
    return;
  }
  context.to(() => ArtistBatchSearchPage(artists: names.toList()));
}
