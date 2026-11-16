part of 'image_favorites_page.dart';

/// 收藏图片的大图翻页图册。
///
/// 两种模式：
/// - [ImageFavoritesPhotoView]：单部漫画，遍历该漫画全部收藏图；
/// - [ImageFavoritesPhotoView.global]：跨漫画全局图册，
///   全部漫画的收藏图按漫画顺序混排，底栏显示当前所属漫画。
class ImageFavoritesPhotoView extends StatefulWidget {
  /// 单部漫画图册：从 [imageFavorite] 开始翻页。
  const ImageFavoritesPhotoView({
    super.key,
    required ImageFavoritesComic comic,
    required ImageFavorite imageFavorite,
  }) : comics = [comic],
       initialImage = imageFavorite;

  /// 跨漫画全局图册：[comics] 里全部收藏图混排翻页。
  const ImageFavoritesPhotoView.global({
    super.key,
    required this.comics,
    this.initialImage,
  }) : assert(comics.length > 0);

  final List<ImageFavoritesComic> comics;

  /// 起始定位的图片；不在列表中或为 null 时从第一张开始。
  final ImageFavorite? initialImage;

  @override
  State<ImageFavoritesPhotoView> createState() =>
      _ImageFavoritesPhotoViewState();
}

class _ImageFavoritesPhotoViewState extends State<ImageFavoritesPhotoView> {
  late PageController controller;
  Map<ImageFavorite, bool> cancelImageFavorites = {};

  /// (所属漫画, 收藏图片) 的混排序列，全局/单漫画模式共用。
  final entries = <(ImageFavoritesComic, ImageFavorite)>[];

  bool get isGlobal => widget.comics.length > 1;

  int currentPage = 0;

  bool isAppBarShow = false;

  @override
  void initState() {
    var current = 0;
    for (var comic in widget.comics) {
      for (var ep in comic.imageFavoritesEp) {
        for (var image in ep.imageFavorites) {
          entries.add((comic, image));
          if (image == widget.initialImage) {
            current = entries.length - 1;
          }
        }
      }
    }
    currentPage = current;
    controller = PageController(initialPage: current);
    super.initState();
  }

  void onPop() {
    List<ImageFavorite> tempList = cancelImageFavorites.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toList();
    if (tempList.isNotEmpty) {
      ImageFavoriteManager().deleteImageFavorite(tempList);
      showToast(
          message: "Delete @a images".tlParams({'a': tempList.length}),
          context: context);
    }
  }

  ImageFavoritesComic get currentComic =>
      entries[currentPage].$1;

  PhotoViewGalleryPageOptions _buildItem(BuildContext context, int index) {
    var image = entries[index].$2;
    return PhotoViewGalleryPageOptions(
      // 图片加载器 支持本地、网络
      imageProvider: ImageFavoritesProvider(image),
      // 初始化大小 全部展示
      minScale: PhotoViewComputedScale.contained * 1.0,
      maxScale: PhotoViewComputedScale.covered * 10.0,
      onTapUp: (context, details, controllerValue) {
        setState(() {
          isAppBarShow = !isAppBarShow;
        });
      },
      heroAttributes: PhotoViewHeroAttributes(
        tag: "${image.sourceKey}${image.id}${image.ep}${image.page}",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return PopScope(
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) {
            onPop();
          }
        },
        child: Scaffold(
          body: Center(child: Text("No images".tl)),
        ),
      );
    }
    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          onPop();
        }
      },
      child: Listener(
        onPointerSignal: (event) {
          if (HardwareKeyboard.instance.isControlPressed) {
            return;
          }
          if (event is PointerScrollEvent) {
            if (event.scrollDelta.dy > 0) {
              if (controller.page! >= entries.length - 1) {
                return;
              }
              controller.nextPage(
                  duration: Duration(milliseconds: 180), curve: Curves.ease);
            } else {
              if (controller.page! <= 0) {
                return;
              }
              controller.previousPage(
                  duration: Duration(milliseconds: 180), curve: Curves.ease);
            }
          }
        },
        child: Stack(children: [
          Positioned.fill(
            child: PhotoViewGallery.builder(
              backgroundDecoration: BoxDecoration(
                color: context.colorScheme.surface,
              ),
              builder: _buildItem,
              itemCount: entries.length,
              loadingBuilder: (context, event) => Center(
                child: SizedBox(
                  width: 20.0,
                  height: 20.0,
                  child: CircularProgressIndicator(
                    backgroundColor: context.colorScheme.surfaceContainerHigh,
                    value: event == null || event.expectedTotalBytes == null
                        ? null
                        : event.cumulativeBytesLoaded /
                            event.expectedTotalBytes!,
                  ),
                ),
              ),
              pageController: controller,
              onPageChanged: (index) {
                setState(() {
                  currentPage = index;
                });
              },
            ),
          ),
          buildPageInfo(),
          AnimatedPositioned(
            top: isAppBarShow ? 0 : -(context.padding.top + 52),
            left: 0,
            right: 0,
            duration: Duration(milliseconds: 180),
            child: buildAppBar(),
          ),
        ]),
      ),
    );
  }

  Widget buildPageInfo() {
    var text = "${currentPage + 1}/${entries.length}";
    // 全局图册：附上当前图片所属的漫画名。
    if (isGlobal) {
      text += "  ·  ${currentComic.title}";
    }
    return Positioned(
      height: 40,
      left: 0,
      right: 0,
      bottom: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.width * 0.86),
          child: Stack(
            children: [
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 1.4
                    ..color = context.colorScheme.onInverseSurface,
                ),
              ),
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildAppBar() {
    return Material(
      color: context.colorScheme.surface.toOpacity(0.72),
      child: BlurEffect(
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: context.colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.close),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isGlobal
                      ? "${"Image Favorites".tl} · ${currentComic.title}"
                      : currentComic.title,
                  style: TextStyle(fontSize: 18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert),
                onPressed: showMenu,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ).paddingTop(context.padding.top),
      ),
    );
  }

  void showMenu() {
    showMenuX(
      context,
      Offset(context.width, context.padding.top),
      [
        MenuEntry(
          icon: Icons.chrome_reader_mode_outlined,
          text: "Details".tl,
          onClick: () {
            var comic = currentComic;
            App.mainNavigatorKey?.currentContext?.to(
              () => ComicPage(id: comic.id, sourceKey: comic.sourceKey),
            );
          },
        ),
        MenuEntry(
          icon: Icons.image_outlined,
          text: "Save Image".tl,
          onClick: () async {
            var temp = entries[currentPage].$2;
            var imageProvider = ImageFavoritesProvider(temp);
            var data = await imageProvider.load(null, null);
            var fileType = detectFileType(data);
            var fileName = "${currentPage + 1}.${fileType.ext}";
            await saveFile(filename: fileName, data: data);
          },
        ),
        MenuEntry(
          icon: Icons.menu_book_outlined,
          text: "Read".tl,
          onClick: () async {
            var comic = currentComic;
            var image = entries[currentPage].$2;
            App.rootContext.to(
              () => ReaderWithLoading(
                id: comic.id,
                sourceKey: comic.sourceKey,
                initialEp: image.ep,
                initialPage: image.page,
              )
            );
          },
        ),
      ],
    );
  }
}
