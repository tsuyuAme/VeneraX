import 'package:flutter/material.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/app_page_route.dart';
import 'package:venera/pages/search_page.dart';

/// Search as a primary sidebar tab with a nested [Navigator] so result pages
/// (aggregated / single-source / comic detail) stay on the stack when switching
/// to Home / Favorites / etc.
///
/// [NavigatorPopHandler] wires Android system back into this nested stack
/// (desktop mouse-back / Esc go through [App.pop]).
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => SearchTabState();
}

class SearchTabState extends State<SearchTab>
    with AutomaticKeepAliveClientMixin {
  final navigatorKey = GlobalKey<NavigatorState>();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    App.secondaryNavigatorKey = navigatorKey;
  }

  @override
  void dispose() {
    if (App.secondaryNavigatorKey == navigatorKey) {
      App.secondaryNavigatorKey = null;
      App.secondaryNavigatorActive = false;
    }
    super.dispose();
  }

  void popToRoot() {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  bool get canPop => navigatorKey.currentState?.canPop() ?? false;

  void pop() {
    if (canPop) {
      navigatorKey.currentState!.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return NavigatorPopHandler(
      onPopWithResult: (result) {
        navigatorKey.currentState?.pop(result);
      },
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (settings) {
          return AppPageRoute(
            preventRebuild: false,
            builder: (context) => const SearchPage(),
          );
        },
      ),
    );
  }
}
