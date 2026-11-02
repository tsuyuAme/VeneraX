part of 'components.dart';

class ComicDescription extends StatelessWidget {
  const ComicDescription({
    super.key,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.enableTranslate,
    this.badge,
    this.maxLines = 2,
    this.tags,
    this.rating,
    this.updateText,
    this.statusText,
    this.progressText,
    this.pagesText,
    this.showTitle = true,
    this.showDescription = true,
    this.onTapAuthor,
    this.onTapTag,
    this.onAuthorOrTagMenu,
    this.enableLongPressCopy = false,
  });

  final String title;
  final String subtitle;
  final String description;
  final String? badge;
  final List<String>? tags;
  final int maxLines;
  final bool enableTranslate;
  final double? rating;
  final String? updateText;
  final String? statusText;
  final String? progressText;
  final String? pagesText;
  final bool showTitle;

  /// Off on the detail page, which renders the full description on its own.
  final bool showDescription;
  final void Function(String author, String? namespace)? onTapAuthor;
  final void Function(String tag, String namespace)? onTapTag;

  /// Long-press / right-click for author or tag (favorite, copy, …).
  final void Function(String value, String? namespace, BuildContext ctx)?
      onAuthorOrTagMenu;

  /// Whether long-pressing an info/tag value copies it to the clipboard.
  /// Enabled on the comic detail page; disabled on list tiles so a long press
  /// over the tag area triggers the tile's own context menu instead (issue #79).
  final bool enableLongPressCopy;

  @override
  Widget build(BuildContext context) {
    final descriptionParts = _descriptionParts();
    final source = _clean(badge) ?? _derivedSource(descriptionParts);
    // Prefer explicit comic/source update time only — never favorite-added date
    // that FavoriteItem packs into description as "YYYY-MM-DD | source".
    final update = _clean(updateText) ?? _updateTextFromTags();
    final progress = _clean(progressText);
    final authorItems = _authorItems();
    final authors = authorItems.isEmpty
        ? null
        : authorItems.map((e) => e.label).join(", ");
    final languageItems = _languageItems();
    final languageLabel = languageItems.isEmpty
        ? null
        : _tagText(languageItems);
    final tagItems = _tagItems();
    final tagText = _tagText(tagItems);
    final status = _clean(statusText) ?? _statusText();
    final isDetail = onTapTag != null;
    // Pages: detail only (list omits them so tags keep room). Prefer the
    // explicit [pagesText] from ComicDetails.maxPage; fall back to pages: tags.
    final pages = isDetail
        ? (_clean(pagesText) ?? _pagesText())
        : null;
    final fallbackDescription = _fallbackDescription(
      update,
      progress,
      source,
      descriptionParts,
    );

    final bodyRows = <Widget>[
      if (authors != null && onTapAuthor != null)
        _actionRow(
          context,
          "Authors".tl,
          authorItems
              .map(
                (item) => _InfoAction(
                  text: item.label,
                  onTap: () => onTapAuthor!(item.value, item.namespace),
                  onMenu: onAuthorOrTagMenu == null
                      ? null
                      : (ctx) => onAuthorOrTagMenu!(
                            item.value,
                            item.namespace,
                            ctx,
                          ),
                ),
              )
              .toList(),
          Colors.lightBlue,
        )
      else if (authors != null)
        _infoRow(context, "Authors".tl, authors, Colors.lightBlue),
      if (source != null) _infoRow(context, "Source".tl, source, Colors.cyan),
      if (tagItems.isNotEmpty && isDetail)
        _actionRow(
          context,
          "Tags".tl,
          tagItems
              .map(
                (item) => _InfoAction(
                  text: item.label,
                  onTap: () => onTapTag!(item.value, item.namespace ?? ''),
                  onMenu: onAuthorOrTagMenu == null
                      ? null
                      : (ctx) => onAuthorOrTagMenu!(
                            item.value,
                            item.namespace,
                            ctx,
                          ),
                ),
              )
              .toList(),
          Colors.pinkAccent,
        )
      else if (tagText != null)
        _tagsTextRow(context, tagText),
      // Detail: same labeled row style as Author / Source.
      if (update != null && isDetail)
        _infoRow(context, "Update Time".tl, update, Colors.teal),
      if (pages != null)
        _infoRow(context, "Pages".tl, pages, Colors.indigo),
      if (status != null) _infoRow(context, "Status".tl, status, Colors.purple),
      if (progress != null)
        _infoRow(context, "Progress".tl, progress, Colors.green),
      if (isDetail && fallbackDescription != null)
        _infoRow(context, "Description".tl, fallbackDescription, Colors.orange),
    ];

    // List only: time bottom-left, language bottom-right, pinned to tile bottom.
    final footer =
        isDetail ? null : _metaFooter(context, update, languageLabel);

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasFooter = footer != null;
        final visibleRows = _visibleRowCount(
          constraints.maxHeight,
          rating != null,
          totalRows: bodyRows.length,
          extraRows: 0,
          reserveFooter: hasFooter,
        );
        final body = <Widget>[
          if (showTitle) ...[
            Text(
              title.trim(),
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              maxLines: bodyRows.isEmpty && !hasFooter ? maxLines : 1,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
            const SizedBox(height: 4),
          ],
          if (rating != null) ...[
            StarRating(value: rating!, size: 15),
            const SizedBox(height: 2),
          ],
          if (bodyRows.isNotEmpty)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: bodyRows.take(visibleRows).toList(),
            ),
        ];
        if (!hasFooter) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: body,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...body,
            const Spacer(),
            footer!,
          ],
        );
      },
    );
  }

  /// Upload/update time from plain description parts (EH puts time there).
  String? _timeFromDescription(List<String> parts) {
    for (final part in parts) {
      if (_looksLikeDate(part)) {
        return _clean(part);
      }
    }
    return null;
  }

  /// Tags as text: at most two lines, then ellipsis.
  Widget _tagsTextRow(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.pinkAccent.toOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                "Tags".tl,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.25,
                color: context.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact footer: time on the left, language on the right.
  Widget? _metaFooter(
    BuildContext context,
    String? time,
    String? language,
  ) {
    if (time == null && language == null) {
      return null;
    }
    final style = TextStyle(
      fontSize: 10,
      height: 1.2,
      color: context.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              time ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: style,
            ),
          ),
          if (language != null)
            Text(
              language,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: style,
            ),
        ],
      ),
    );
  }

  /// Rows the tile can draw.
  ///
  /// An unbounded height means the host scrolls (the detail page) rather than
  /// clipping, so every row is drawn there; only a fixed-height tile has to
  /// choose. [reserveFooter] keeps space for the time/language footer.
  int _visibleRowCount(
    double maxHeight,
    bool hasRating, {
    required int totalRows,
    int extraRows = 0,
    bool reserveFooter = false,
  }) {
    if (maxHeight.isInfinite) {
      return totalRows;
    }
    final reservedHeight = (showTitle ? 24 : 0) +
        (hasRating ? 20 : 0) +
        (reserveFooter ? 14 : 0);
    final count = ((maxHeight - reservedHeight) / 21).floor();
    // Prefer showing tags: allow up to 6 body rows when height permits.
    return math.max(1, math.min(6 + extraRows, count));
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    context.showMessage(message: "Copied".tl);
  }

  Widget _infoRow(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color.toOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: () {
              final valueText = Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colorScheme.onSurfaceVariant,
                ),
              );
              if (!enableLongPressCopy) {
                return valueText;
              }
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _copy(context, value),
                child: valueText,
              );
            }(),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    BuildContext context,
    String label,
    List<_InfoAction> actions,
    Color color, {
    int? maxLines,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color.toOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
                    spacing: 0,
                    runSpacing: 2,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        Builder(
                          builder: (chipCtx) {
                            return InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: actions[i].onTap,
                              onLongPress: () {
                                if (actions[i].onMenu != null) {
                                  actions[i].onMenu!(chipCtx);
                                } else if (enableLongPressCopy) {
                                  _copy(context, actions[i].text);
                                }
                              },
                              onSecondaryTap: actions[i].onMenu == null
                                  ? null
                                  : () => actions[i].onMenu!(chipCtx),
                              child: Text(
                                actions[i].text,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.colorScheme.primary,
                                ),
                              ).paddingHorizontal(2),
                            );
                          },
                        ),
                        if (i != actions.length - 1)
                          Text(
                            " / ",
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ],
                  )
          ),
        ],
      ),
    );
  }

  String? _clean(String? value) {
    final result = value?.replaceAll("\n", " ").trim();
    return result == null ||
            result.isEmpty ||
            result == "Unknown" ||
            result.startsWith("Unknown:")
        ? null
        : result;
  }

  String? _tagText(List<_DescriptionTag> rawTags) {
    if (rawTags.isEmpty) {
      return null;
    }
    return rawTags.map((tag) => tag.label).join(" / ");
  }

  /// Language tags, shown in a row of their own (issue #288).
  List<_DescriptionTag> _languageItems() {
    return _tagItemsWithNamespace(_languageNamespaces);
  }

  /// Content tags, minus language ones — those get their own row.
  List<_DescriptionTag> _tagItems() {
    final rawTags = tags
        ?.map((e) => e.replaceAll("\n", " ").trim())
        .where(
          (e) =>
              e.removeAllBlank != "" &&
              !_isMetadataTag(e) &&
              !_isLanguageTag(e) &&
              _clean(e.split(':').last) != null,
        )
        .toList();
    if (rawTags == null || rawTags.isEmpty) {
      return const [];
    }
    final enableTranslate =
        App.locale.languageCode == 'zh' && this.enableTranslate;
    return rawTags.map((tag) {
      final index = tag.indexOf(':');
      final namespace = index == -1 ? null : tag.substring(0, index);
      final value = index == -1 ? tag : tag.substring(index + 1);
      return _DescriptionTag(
        namespace: namespace,
        value: value,
        label: enableTranslate
            ? TagsTranslation.translateTag(tag)
            : tag.split(':').last,
      );
    }).toList();
  }

  List<_DescriptionTag> _authorItems() {
    final author = _clean(subtitle);
    if (author != null) {
      return author
          .split(RegExp(r"[|,]"))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map(
            (e) => _DescriptionTag(
              namespace: _namespaceForValue(e, _authorNamespaces),
              value: e,
              label: e,
            ),
          )
          .toList();
    }
    return _tagItemsWithNamespace(_authorNamespaces);
  }

  String? _statusText() {
    return _tagsWithNamespace(_statusNamespaces).firstOrNull;
  }

  /// Page count from a `pages:` style tag, for sources that report it that way
  /// instead of through [Comic.maxPage].
  String? _pagesText() {
    return _tagsWithNamespace(_pagesNamespaces).firstOrNull;
  }

  String? _updateTextFromTags() {
    return _tagsWithNamespace(
      _updateNamespaces,
    ).where(_looksLikeDate).firstOrNull;
  }

  List<String> _tagsWithNamespace(Set<String> namespaces) {
    return _tagItemsWithNamespace(namespaces).map((e) => e.label).toList();
  }

  List<_DescriptionTag> _tagItemsWithNamespace(Set<String> namespaces) {
    return tags
            ?.map((e) => e.replaceAll("\n", " ").trim())
            .where((e) => e.contains(':'))
            .map((e) {
              final index = e.indexOf(':');
              final namespace = _normalizeNamespace(e.substring(0, index));
              final value = _clean(e.substring(index + 1));
              if (value == null || !namespaces.contains(namespace)) {
                return null;
              }
              return _DescriptionTag(
                namespace: e.substring(0, index),
                value: value,
                label: enableTranslate && App.locale.languageCode == 'zh'
                    ? TagsTranslation.translateTag(e)
                    : value,
              );
            })
            .whereType<_DescriptionTag>()
            .toList() ??
        const [];
  }

  String? _namespaceForValue(String value, Set<String> namespaces) {
    for (final tag in tags ?? const <String>[]) {
      final index = tag.indexOf(':');
      if (index == -1) {
        continue;
      }
      final namespace = tag.substring(0, index);
      final tagValue = _clean(tag.substring(index + 1));
      if (tagValue == value &&
          namespaces.contains(_normalizeNamespace(namespace))) {
        return namespace;
      }
    }
    return null;
  }

  bool _isLanguageTag(String tag) {
    final index = tag.indexOf(':');
    if (index <= 0) return false;
    return _languageNamespaces.contains(
      _normalizeNamespace(tag.substring(0, index)),
    );
  }

  bool _isMetadataTag(String tag) {
    if (!tag.contains(':')) {
      final value = _clean(tag);
      return value == null || _looksLikeDate(value) || _looksLikeStatus(value);
    }
    final index = tag.indexOf(':');
    final namespace = _normalizeNamespace(tag.substring(0, index));
    final value = _clean(tag.substring(index + 1));
    return _metadataNamespaces.contains(namespace) ||
        value == null ||
        _looksLikeDate(value) ||
        _looksLikeStatus(value);
  }

  String _normalizeNamespace(String value) {
    return value.trim().toLowerCase().replaceAll(' ', '');
  }

  static const _authorNamespaces = {
    'author',
    'artist',
    'authors',
    'artists',
    'creator',
    '原作',
    '作者',
    '作家',
    '作画',
    '作畫',
    '漫畫',
    '漫画',
    '著者',
    '绘师',
    '繪師',
  };

  static const _statusNamespaces = {
    'status',
    'state',
    'serialization',
    '連載',
    '连载',
    '狀態',
    '状态',
  };

  static const _updateNamespaces = {
    'date',
    'lastupdate',
    'time',
    'update',
    'updated',
    '更新',
    '最後更新',
    '最后更新',
    '時間',
    '时间',
    '日期',
  };

  static const _pagesNamespaces = {'page', 'pages', '頁數', '页数'};

  static const _languageNamespaces = {
    'language',
    'languages',
    'lang',
    '語言',
    '语言',
  };

  // 'language' is deliberately absent here: nothing renders metadata rows for
  // it, so listing it made language tags vanish rather than move (issue #288).
  static const _metadataNamespaces = {
    ..._authorNamespaces,
    ..._statusNamespaces,
    ..._updateNamespaces,
    ..._pagesNamespaces,
    'source',
    'uploader',
    '來源',
    '来源',
    '上傳者',
    '上传者',
  };

  String? _derivedSource(List<String> parts) {
    if (parts.length != 2 || !_looksLikeDate(parts.first)) {
      return null;
    }
    return _clean(parts.last);
  }

  String? _fallbackDescription(
    String? update,
    String? progress,
    String? source,
    List<String> parts,
  ) {
    final value = _clean(description);
    if (value == null || value == update || value == progress) {
      return null;
    }
    if (_isMetadataDescription(parts, source)) {
      return null;
    }
    return value.replaceAll("|", " / ");
  }

  List<String> _descriptionParts() {
    return description
        .split("|")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool _looksLikeDate(String value) {
    return RegExp(r"^\d{4}[-/]\d{1,2}[-/]\d{1,2}").hasMatch(value) ||
        RegExp(r"^\d{4}").hasMatch(value);
  }

  bool _looksLikeStatus(String value) {
    final normalized = value.trim().toLowerCase();
    return const {
      'completed',
      'complete',
      'ongoing',
      'serializing',
      '連載',
      '連載中',
      '连载',
      '连载中',
      '完結',
      '完结',
      '已完結',
      '已完结',
      '休載',
      '休载',
    }.contains(normalized);
  }

  bool _isMetadataDescription(List<String> parts, String? source) {
    if (parts.length != 2 || !_looksLikeDate(parts.first)) {
      return false;
    }
    final descriptionSource = _clean(parts.last);
    return source == null ||
        descriptionSource == null ||
        descriptionSource == source;
  }
}

class _DescriptionTag {
  const _DescriptionTag({
    required this.value,
    required this.label,
    this.namespace,
  });

  final String? namespace;
  final String value;
  final String label;
}

class _InfoAction {
  const _InfoAction({
    required this.text,
    required this.onTap,
    this.onMenu,
  });

  final String text;
  final VoidCallback onTap;
  final void Function(BuildContext ctx)? onMenu;
}
