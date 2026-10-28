import 'package:flutter/material.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/pages/aggregated_search_page.dart';
import 'package:venera/pages/search/artist_favorites_page.dart';
import 'package:venera/pages/search/search_shortcuts.dart';
import 'package:venera/pages/search/artist_batch_search_page.dart';
import 'package:venera/utils/translations.dart';

/// Home section body for favorited artists.
class ArtistFavoritesHomeSection extends StatefulWidget {
  const ArtistFavoritesHomeSection({super.key});

  @override
  State<ArtistFavoritesHomeSection> createState() =>
      _ArtistFavoritesHomeSectionState();
}

class _ArtistFavoritesHomeSectionState
    extends State<ArtistFavoritesHomeSection> {
  int _count = 0;
  List<String> _preview = const [];

  void _refresh() {
    final names = <String>{};
    for (final s in SearchShortcutManager.instance.all) {
      if (s.isAuthor) names.add(s.value);
    }
    final list = names.toList();
    if (mounted) {
      setState(() {
        _count = list.length;
        _preview = list.take(12).toList();
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_preview.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'Long-press an author on a comic page to favorite'.tl,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in _preview)
                  ActionChip(
                    label: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () {
                      context.to(() => AggregatedSearchPage(keyword: name));
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.manage_search, size: 18),
                  label: Text('Search all'.tl),
                  onPressed: () => openArtistBatchSearch(context),
                ),
                if (_count > _preview.length)
                  ActionChip(
                    avatar: const Icon(Icons.more_horiz, size: 18),
                    label: Text('View more'.tl),
                    onPressed: () {
                      context.to(() => const ArtistFavoritesPage());
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
