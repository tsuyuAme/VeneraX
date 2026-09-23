
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/comic_state_repository.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/search/search_shortcuts.dart';
import 'package:venera/utils/translations.dart';

const _kSearchTimeout = Duration(seconds: 20);

/// Search favorited authors and merge results into one list sorted by time.
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
  /// Sources that returned zero comics or failed/timed out (for page 1 banner).
  final List<String> _emptyOrFailed = [];
  bool _bannerShown = false;

  DateTime? _comicDate(Comic c) {
    // Prefer structured fields, then description fragments.
    final candidates = <String?>[
      c is FavoriteItemWithUpdateInfo ? c.updateTime : null,
      // Comic has no updateTime on base interface always - try description
      ...c.description.split(RegExp(r'[|/\n]')).map((e) => e.trim()),
    ];
    DateTime? best;
    for (final raw in candidates) {
      if (raw == null || raw.isEmpty) continue;
      final m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(raw);
      if (m == null) continue;
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      final d = int.tryParse(m.group(3)!);
      if (y == null || mo == null || d == null) continue;
      try {
        final dt = DateTime(y, mo, d);
        if (best == null || dt.isAfter(best)) best = dt;
      } catch (_) {}
    }
    return best;
  }

  int _compareByTimeDesc(Comic a, Comic b) {
    final da = _comicDate(a);
    final db = _comicDate(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  }

  Future<Res<List<Comic>>?> _searchOne(
    ComicSource source,
    String artist,
    int page,
  ) async {
    final data = source.searchPageData;
    if (data == null) return null;
    final options =
        (data.searchOptions ?? []).map((e) => e.defaultValue).toList();
    try {
      final future = () async {
        if (data.loadPage != null) {
          return await data.loadPage!(artist, page, options);
        }
        if (data.loadNext != null) {
          if (page != 1) return const Res(<Comic>[]);
          return await data.loadNext!(artist, null, options);
        }
        return const Res(<Comic>[]);
      }();
      return await future.timeout(_kSearchTimeout);
    } on TimeoutException {
      return Res.error('Timeout');
    } catch (e) {
      return Res.error(e.toString());
    }
  }

  Future<Res<List<Comic>>> _loadPage(int page) async {
    if (widget.artists.isEmpty) return const Res([]);
    if (widget.sources.isEmpty) {
      return Res.error('No Search Sources'.tl);
    }

    final seen = <String>{};
    final out = <Comic>[];
    // Per-source: any success with comics / empty / error
    final sourceHadComics = {for (final s in widget.sources) s.key: false};
    final sourceFailed = <String, String>{};

    const concurrency = 4;
    var index = 0;
    final tasks = <({ComicSource source, String artist})>[
      for (final artist in widget.artists)
        for (final source in widget.sources) (source: source, artist: artist),
    ];

    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= tasks.length) return;
        final t = tasks[i];
        final res = await _searchOne(t.source, t.artist, page);
        if (res == null) continue;
        if (res.error) {
          sourceFailed.putIfAbsent(
            t.source.key,
            () => res.errorMessage ?? 'error',
          );
          continue;
        }
        final list = res.data ?? const <Comic>[];
        if (list.isNotEmpty) {
          sourceHadComics[t.source.key] = true;
        }
        for (final c in list) {
          final key = '${c.sourceKey}\u0000${c.id}';
          if (seen.add(key)) out.add(c);
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));

    // Sort newest first (sources that omit dates sink to the bottom).
    out.sort(_compareByTimeDesc);

    if (page == 1) {
      _emptyOrFailed
        ..clear()
        ..addAll([
          for (final s in widget.sources)
            if (sourceHadComics[s.key] != true)
              sourceFailed.containsKey(s.key)
                  ? '${s.name} (${'failed or timeout'.tl})'
                  : '${s.name} (${'no results'.tl})',
        ]);
    }

    if (out.isEmpty && sourceFailed.isNotEmpty && sourceHadComics.values.every((v) => !v)) {
      return Res.error(
        sourceFailed.entries.map((e) {
          final name =
              ComicSource.find(e.key)?.name ?? e.key;
          return '$name: ${e.value}';
        }).join('\n'),
      );
    }
    return Res(out);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = '@n authors · @s sources'
        .tl
        .replaceAll('@n', '${widget.artists.length}')
        .replaceAll('@s', '${widget.sources.length}');

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
        loadPage: (page) async {
          final res = await _loadPage(page);
          if (page == 1 &&
              mounted &&
              !_bannerShown &&
              _emptyOrFailed.isNotEmpty) {
            _bannerShown = true;
            // Defer message to next frame so list can paint first.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              context.showMessage(
                message:
                    '${'No results or failed'.tl}: ${_emptyOrFailed.join(', ')}',
              );
            });
          }
          return res;
        },
        scrollbarTopPadding: context.padding.top + 56,
      ),
    );
  }
}

List<ComicSource> _searchableSources() {
  final all =
      ComicSource.all().where((e) => e.searchPageData != null).toList();
  final settings = appdata.settings['searchSources'];
  if (settings is! List || settings.isEmpty) return all;
  final keys = settings.whereType<String>().toSet();
  final filtered = all.where((s) => keys.contains(s.key)).toList();
  return filtered.isEmpty ? all : filtered;
}

/// Chip-style source picker (none selected by default), then batch search.
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
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: mathMin(ctx),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Select sources'.tl,
                          style: Theme.of(ctx).textTheme.titleSmall,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              selected
                                ..clear()
                                ..addAll(candidates.map((e) => e.key));
                            });
                          },
                          child: Text('Select All'.tl),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => selected.clear());
                          },
                          child: Text('Deselect All'.tl),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in candidates)
                          FilterChip(
                            label: Text(s.name),
                            selected: selected.contains(s.key),
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  selected.add(s.key);
                                } else {
                                  selected.remove(s.key);
                                }
                              });
                            },
                          ),
                      ],
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

double mathMin(BuildContext ctx) {
  final h = MediaQuery.sizeOf(ctx).height;
  return h > 120 ? h * 0.55 : 360;
}
