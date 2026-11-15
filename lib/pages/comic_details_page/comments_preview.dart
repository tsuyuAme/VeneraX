part of 'comic_page.dart';

class _CommentsPart extends StatefulWidget {
  const _CommentsPart({required this.comments, required this.showMore});

  final List<Comment> comments;

  final void Function() showMore;

  @override
  State<_CommentsPart> createState() => _CommentsPartState();
}

class _CommentsPartState extends State<_CommentsPart> {
  final scrollController = ScrollController();

  late List<Comment> comments;

  /// One comment card width + margin. Used for multi-step chevron jumps.
  double _itemExtent = 332;

  @override
  void initState() {
    comments = widget.comments.where((c) => !_shouldBlockComment(c)).toList();
    super.initState();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  /// Phone: 1 card; desktop: 4 cards per chevron click.
  int get _scrollStepCount {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return wide ? 4 : 1;
  }

  void _scrollBy(double delta) {
    if (!scrollController.hasClients) return;
    final target = (scrollController.position.pixels + delta).clamp(
      0.0,
      scrollController.position.maxScrollExtent,
    );
    scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    final cardWidth = math.min(324.0, math.max(240.0, context.width - 56));
    _itemExtent = cardWidth + 8;
    final step = _itemExtent * _scrollStepCount;
    return MultiSliver(
      children: [
        SliverLazyToBoxAdapter(
          child: _ComicSectionHeader(
            icon: Icons.forum_outlined,
            title: "Comments".tl,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (context.width >= 600) ...[
                  IconButton(
                    tooltip: "Previous".tl,
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => _scrollBy(-step),
                  ),
                  IconButton(
                    tooltip: "Next".tl,
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => _scrollBy(step),
                  ),
                ],
                TextButton(
                  onPressed: widget.showMore,
                  child: Text("View more".tl),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 220,
                child: MediaQuery.removePadding(
                  removeTop: true,
                  context: context,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      // Enable mouse drag-to-scroll on desktop.
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                      },
                    ),
                    child: ListView.builder(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    // Desktop: allow click-drag + mouse wheel / trackpad.
                    primary: false,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      return _CommentWidget(
                        comment: comments[index],
                        width: cardWidth,
                      );
                    },
                  ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentWidget extends StatelessWidget {
  const _CommentWidget({required this.comment, required this.width});

  final Comment comment;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      width: width,
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (comment.avatar != null)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: context.colorScheme.surfaceContainer,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image(
                    image: CachedImageProvider(comment.avatar!),
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  ),
                ).paddingRight(8),
              Text(comment.userName, style: ts.bold),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: RichCommentContent(
                text: comment.content,
                // Show linked thumbnails (EH image-as-link comments).
                showImages: true,
                // Horizontal list: avoid SelectableText stealing link taps.
                selectable: false,
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (comment.time != null)
            Text(comment.time!, style: ts.s12).toAlign(Alignment.centerLeft),
        ],
      ),
    );
  }
}
