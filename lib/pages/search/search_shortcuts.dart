import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/pages/aggregated_search_page.dart';
import 'package:venera/pages/search/artist_favorites_page.dart';
import 'package:venera/utils/tags_translation.dart';
import 'package:venera/utils/translations.dart';

enum SearchShortcutKind { author, tag }

class SearchShortcut {
  const SearchShortcut({
    required this.kind,
    required this.sourceKey,
    required this.namespace,
    required this.value,
    this.rawValue,
  });

  final SearchShortcutKind kind;
  final String sourceKey;
  final String namespace;
  /// Display / aggregated-search name (may be translated 原名).
  final String value;
  /// Original source tag (e.g. EH romanized artist) for tag-based search.
  final String? rawValue;

  bool get isAuthor => kind == SearchShortcutKind.author;

  String get searchValue => (rawValue != null && rawValue!.isNotEmpty)
      ? rawValue!
      : value;

  String get identity =>
      '$sourceKey\u0000${kind.name}\u0000$namespace\u0000$searchValue';

  Map<String, dynamic> toJson() {
    return {
      'kind': kind.name,
      'sourceKey': sourceKey,
      'namespace': namespace,
      'value': value,
      if (rawValue != null && rawValue!.isNotEmpty) 'rawValue': rawValue,
    };
  }

  static SearchShortcut? fromJson(dynamic value) {
    if (value is! Map) return null;
    final kindValue = value['kind'];
    final sourceKey = value['sourceKey'];
    final namespace = value['namespace'];
    final shortcutValue = value['value'];
    if (kindValue is! String ||
        sourceKey is! String ||
        namespace is! String ||
        shortcutValue is! String ||
        sourceKey.trim().isEmpty ||
        namespace.trim().isEmpty ||
        shortcutValue.trim().isEmpty) {
      return null;
    }
    final kind = switch (kindValue) {
      'author' => SearchShortcutKind.author,
      'tag' => SearchShortcutKind.tag,
      _ => null,
    };
    if (kind == null) return null;
    final raw = value['rawValue'];
    return SearchShortcut(
      kind: kind,
      sourceKey: sourceKey.trim(),
      namespace: namespace.trim(),
      value: shortcutValue.trim(),
      rawValue: raw is String && raw.trim().isNotEmpty ? raw.trim() : null,
    );
  }
}

bool isAuthorNamespace(String namespace) {
  const names = {
    'author',
    'authors',
    'artist',
    'artists',
    'creator',
    '原作',
    '作者',
    '作家',
    '作画',
    '作畫',
    '画师',
    '畫師',
    '绘师',
    '繪師',
  };
  return names.contains(namespace.trim().toLowerCase().replaceAll(' ', ''));
}

/// Bare tag text only (never "artist:xxx"). Optional local translation for UI.
String resolveAuthorFavoriteName(String tag, String namespace) {
  var bare = tag.trim();
  // Guard against callers that pass "artist:name" as the tag body.
  final colon = bare.indexOf(':');
  if (colon > 0) {
    final maybeNs = bare.substring(0, colon).trim().toLowerCase();
    if (isAuthorNamespace(maybeNs)) {
      bare = bare.substring(colon + 1).trim();
    }
  }
  final ns = namespace.toLowerCase();
  if (App.locale.languageCode == 'zh') {
    final translated =
        TagsTranslation.translationTagWithNamespace(bare, ns);
    if (translated.isNotEmpty &&
        translated != bare &&
        translated.toLowerCase() != bare.toLowerCase()) {
      return translated;
    }
  }
  return bare;
}

class SearchShortcutManager extends ChangeNotifier {
  SearchShortcutManager._() {
    appdata.settings.addListener(_onSettingsChanged);
  }

  static final instance = SearchShortcutManager._();

  List<SearchShortcut> get all {
    final raw = appdata.settings['searchShortcuts'];
    if (raw is! List) return const [];
    return raw
        .map(SearchShortcut.fromJson)
        .whereType<SearchShortcut>()
        .toList(growable: false);
  }

  bool contains(SearchShortcut shortcut) {
    return all.any((item) => item.identity == shortcut.identity);
  }

  void add(SearchShortcut shortcut) {
    if (contains(shortcut)) return;
    final items = all.toList()..add(shortcut);
    appdata.settings['searchShortcuts'] =
        items.map((item) => item.toJson()).toList();
    unawaited(appdata.saveData());
    notifyListeners();
  }

  void remove(SearchShortcut shortcut) {
    final items = all
        .where((item) => item.identity != shortcut.identity)
        .map((item) => item.toJson())
        .toList();
    appdata.settings['searchShortcuts'] = items;
    unawaited(appdata.saveData());
    notifyListeners();
  }

  /// Remove every author shortcut with the same display/raw name.
  void removeAuthorByName(String name) {
    final items = all.where((item) {
      if (!item.isAuthor) return true;
      return item.value != name && item.searchValue != name;
    }).map((item) => item.toJson()).toList();
    appdata.settings['searchShortcuts'] = items;
    unawaited(appdata.saveData());
    notifyListeners();
  }

  void toggle(SearchShortcut shortcut) {
    if (contains(shortcut)) {
      remove(shortcut);
    } else {
      add(shortcut);
    }
  }

  void _onSettingsChanged() {
    notifyListeners();
  }
}

void openSearchShortcut(BuildContext context, SearchShortcut shortcut) {
  // Aggregated / cross-source search: always the bare name, never "artist:xxx".
  // (EH's onClickTag builds "artist:name" which is only valid inside EH.)
  final keyword = shortcut.value.trim();
  context.to(() => AggregatedSearchPage(keyword: keyword));
}

/// Open within the original source only (keeps EH `artist:` tag search).
void openSearchShortcutInSource(BuildContext context, SearchShortcut shortcut) {
  final source = ComicSource.find(shortcut.sourceKey);
  final tagValue = shortcut.searchValue;
  final target =
      source?.handleClickTagEvent?.call(shortcut.namespace, tagValue);
  if (target != null) {
    target.jump(context);
    return;
  }
  context.to(() => AggregatedSearchPage(keyword: shortcut.value));
}


/// Confirm favoriting an author; user can edit the stored name.
/// Optional dropdown lists bare tag + local translation when they differ.
Future<void> showFavoriteAuthorDialog({
  required BuildContext context,
  required SearchShortcut draft,
}) async {
  final bare = (draft.rawValue ?? draft.value).trim();
  final translated = resolveAuthorFavoriteName(bare, draft.namespace);
  final candidates = <String>[];
  for (final name in [translated, bare, draft.value]) {
    final n = name.trim();
    if (n.isEmpty) continue;
    if (!candidates.any((c) => c.toLowerCase() == n.toLowerCase())) {
      candidates.add(n);
    }
  }
  var text = candidates.isNotEmpty ? candidates.first : bare;
  final controller = TextEditingController(text: text);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return ContentDialog(
            title: 'Favorite author'.tl,
            content: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Edit the name used for search and display.'.tl,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (candidates.length > 1) ...[
                    Text('Suggestions'.tl, style: Theme.of(ctx).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: candidates.contains(text) ? text : candidates.first,
                      items: [
                        for (final c in candidates)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          text = v;
                          controller.text = v;
                        });
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: 'Author name'.tl,
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                    onChanged: (v) => text = v,
                    onSubmitted: (_) => Navigator.of(ctx).pop(true),
                  ),
                ],
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

  if (ok != true) {
    controller.dispose();
    return;
  }
  final name = controller.text.trim();
  controller.dispose();
  if (name.isEmpty) {
    context.showMessage(message: 'Author name'.tl);
    return;
  }
  final saved = SearchShortcut(
    kind: SearchShortcutKind.author,
    sourceKey: draft.sourceKey,
    namespace: draft.namespace,
    value: name,
    // Keep romanized/original tag for source-specific search when edited.
    rawValue: bare.isNotEmpty && bare.toLowerCase() != name.toLowerCase()
        ? bare
        : draft.rawValue,
  );
  SearchShortcutManager.instance.add(saved);
  if (context.mounted) {
    context.showMessage(message: 'Search shortcut saved'.tl);
  }
}

void showSearchShortcutMenu({
  required BuildContext context,
  required Offset location,
  required String copyText,
  SearchShortcut? shortcut,
}) {
  final manager = SearchShortcutManager.instance;
  final entries = <MenuEntry>[
    MenuEntry(
      icon: Icons.copy,
      text: 'Copy'.tl,
      onClick: () {
        Clipboard.setData(ClipboardData(text: copyText));
        context.showMessage(message: 'Copied'.tl);
      },
    ),
  ];
  if (shortcut != null) {
    final saved = manager.contains(shortcut);
    entries.add(
      MenuEntry(
        icon: saved ? Icons.bookmark_remove : Icons.bookmark_add,
        text: saved
            ? (shortcut.isAuthor
                ? 'Unfavorite author'.tl
                : 'Remove tag shortcut'.tl)
            : (shortcut.isAuthor
                ? 'Favorite author'.tl
                : 'Save tag shortcut'.tl),
        onClick: () {
          if (saved) {
            manager.remove(shortcut);
            context.showMessage(message: 'Search shortcut removed'.tl);
            return;
          }
          if (shortcut.isAuthor) {
            // Confirm + edit display name before saving.
            showFavoriteAuthorDialog(context: context, draft: shortcut);
            return;
          }
          manager.add(shortcut);
          context.showMessage(message: 'Search shortcut saved'.tl);
        },
      ),
    );
    if (shortcut.isAuthor) {
      entries.add(
        MenuEntry(
          icon: Icons.search,
          text: 'Aggregated Search'.tl,
          onClick: () {
            context.to(
              () => AggregatedSearchPage(keyword: shortcut.value),
            );
          },
        ),
      );
    }
  }
  showMenuX(context, location, entries);
}

class SearchShortcutsSliver extends StatefulWidget {
  const SearchShortcutsSliver({super.key});

  @override
  State<SearchShortcutsSliver> createState() => _SearchShortcutsSliverState();
}

class _SearchShortcutsSliverState extends State<SearchShortcutsSliver> {
  final manager = SearchShortcutManager.instance;
  static const int _previewLimit = 5;
  bool _sectionExpanded = true;
  bool _tagsExpanded = false;

  @override
  void initState() {
    manager.addListener(_update);
    super.initState();
  }

  @override
  void dispose() {
    manager.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = manager.all;
    if (shortcuts.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final authors =
        shortcuts.where((s) => s.isAuthor).toList(growable: false);
    final tags =
        shortcuts.where((s) => !s.isAuthor).toList(growable: false);
    final previewAuthors =
        authors.take(_previewLimit).toList(growable: false);
    final visibleTags = _tagsExpanded
        ? tags
        : tags.take(_previewLimit).toList(growable: false);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bookmarks_outlined),
            title: Text('Search shortcuts'.tl),
            subtitle: Text('${shortcuts.length}'),
            trailing: Icon(
              _sectionExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () {
              setState(() => _sectionExpanded = !_sectionExpanded);
            },
          ),
          if (_sectionExpanded) ...[
            if (authors.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  'Favorite authors'.tl,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final shortcut in previewAuthors)
                _buildItem(context, shortcut),
              if (authors.length > _previewLimit)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('View more'.tl),
                  subtitle: Text('${authors.length}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.to(() => const ArtistFavoritesPage());
                  },
                ),
            ],
            if (tags.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  'Saved tag searches'.tl,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final shortcut in visibleTags) _buildItem(context, shortcut),
              if (!_tagsExpanded && tags.length > _previewLimit)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('View more'.tl),
                  trailing: const Icon(Icons.expand_more),
                  onTap: () {
                    setState(() => _tagsExpanded = true);
                  },
                ),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _buildItem(BuildContext context, SearchShortcut shortcut) {
    final sourceName =
        ComicSource.find(shortcut.sourceKey)?.name ?? shortcut.sourceKey;
    return Builder(
      builder: (itemContext) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(shortcut.value, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            shortcut.isAuthor
                ? '${'Author'.tl} · $sourceName'
                : '${shortcut.namespace} · $sourceName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => openSearchShortcut(itemContext, shortcut),
          onLongPress: () {
            final box = itemContext.findRenderObject() as RenderBox;
            final offset = box.localToGlobal(Offset.zero);
            showSearchShortcutMenu(
              context: itemContext,
              location: Offset(
                offset.dx + box.size.width / 2 - 121,
                offset.dy + box.size.height - 8,
              ),
              copyText: shortcut.value,
              shortcut: shortcut,
            );
          },
          onSecondaryTapUp: (details) {
            showSearchShortcutMenu(
              context: itemContext,
              location: details.globalPosition,
              copyText: shortcut.value,
              shortcut: shortcut,
            );
          },
        );
      },
    );
  }
}
