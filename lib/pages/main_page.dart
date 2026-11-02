import 'package:flutter/material.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/pages/categories_page.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/random_comic_draw_dialog.dart';
import 'package:venera/pages/search_tab.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/pages/tasks_page.dart';
import 'package:venera/utils/translations.dart';

import '../components/components.dart';
import '../foundation/app.dart';
import 'explore_page.dart';
import 'favorites/favorites_page.dart';
import 'home_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late final NaviObserver _observer;

  GlobalKey<NavigatorState>? _navigatorKey;

  /// Index of the Search tab in [_pages] / paneItems.
  static const int searchTabIndex = 1;

  final GlobalKey<SearchTabState> _searchTabKey = GlobalKey<SearchTabState>();

  late final List<Widget> _pages;

  var index = 0;

  void to(Widget Function() widget, {bool preventDuplicate = false}) async {
    if (preventDuplicate) {
      var page = widget();
      if ("/${page.runtimeType}" == _observer.routes.last.toString()) return;
    }
    _navigatorKey!.currentContext!.to(widget);
  }

  void back() {
    _navigatorKey!.currentContext!.pop();
  }

  /// Switch to Search tab (and optionally reset nested stack).
  void openSearchTab({bool popToRoot = false}) {
    if (popToRoot) {
      _searchTabKey.currentState?.popToRoot();
    }
    NaviPane.of(context).currentPage = searchTabIndex;
  }

  @override
  void initState() {
    super.initState();
    _observer = NaviObserver();
    _navigatorKey = GlobalKey();
    App.mainNavigatorKey = _navigatorKey;
    _pages = [
      const HomePage(),
      SearchTab(key: _searchTabKey),
      const FavoritesPage(key: PageStorageKey('favorites')),
      const ExplorePage(key: PageStorageKey('explore')),
      const CategoriesPage(key: PageStorageKey('categories')),
    ];
    index = int.tryParse(appdata.settings['initialPage'].toString()) ?? 0;
    // Old installs used a 4-tab index; clamp after Search was inserted.
    if (index < 0 || index >= _pages.length) {
      index = 0;
    }
    App.secondaryNavigatorActive = index == searchTabIndex;
  }

  @override
  Widget build(BuildContext context) {
    return NaviPane(
      initialPage: index,
      observer: _observer,
      navigatorKey: _navigatorKey!,
      paneItems: [
        PaneItemEntry(
          label: 'Home'.tl,
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
        ),
        PaneItemEntry(
          label: 'Search'.tl,
          icon: Icons.search,
          activeIcon: Icons.search,
        ),
        PaneItemEntry(
          label: 'Favorites'.tl,
          icon: Icons.local_activity_outlined,
          activeIcon: Icons.local_activity,
        ),
        PaneItemEntry(
          label: 'Explore'.tl,
          icon: Icons.explore_outlined,
          activeIcon: Icons.explore,
        ),
        PaneItemEntry(
          label: 'Categories'.tl,
          icon: Icons.category_outlined,
          activeIcon: Icons.category,
        ),
      ],
      onPageChanged: (i) {
        setState(() {
          index = i;
        });
        App.secondaryNavigatorActive = i == searchTabIndex;
      },
      paneActions: [
        PaneActionEntry(
          icon: Icons.style_outlined,
          label: 'Draw a comic'.tl,
          onTap: () async {
            final comic = await showRandomComicDrawDialog(context);
            if (!mounted || comic == null) return;
            to(
              () => ComicPage(
                id: comic.id,
                sourceKey: comic.sourceKey,
                cover: comic.cover,
                title: comic.title,
              ),
            );
          },
        ),
        PaneActionEntry(
          icon: Icons.assignment_outlined,
          label: "Tasks".tl,
          onTap: () {
            to(() => const TasksPage(), preventDuplicate: true);
          },
        ),
        PaneActionEntry(
          icon: Icons.settings,
          label: "Settings".tl,
          onTap: () {
            to(() => const SettingsPage(), preventDuplicate: true);
          },
        ),
      ],
      pageBuilder: (pageIndex) {
        // Keep tabs alive so Search nested results survive switching away.
        return IndexedStack(
          index: pageIndex,
          sizing: StackFit.expand,
          children: _pages,
        );
      },
    );
  }
}
