VeneraX patch package
=====================

Copy each file over the matching path in your VeneraX repo (paths inside lib/ are relative to repo root).

New file:
  lib/pages/search_tab.dart

Modified:
  lib/pages/main_page.dart
  lib/pages/home_page.dart
  lib/pages/search_result_page.dart
  lib/foundation/app.dart
  lib/components/navigation_bar.dart
  lib/components/rich_comment_content.dart
  lib/pages/comic_details_page/comments_preview.dart
  lib/pages/reader/reader.dart
  lib/pages/reader/images.dart
  lib/utils/app_links.dart

EH date seek (optional, source-side):
  doc/ehentai_seek_snippet.js  → merge into your ehentai/exhentai comic source JS

Features:
  1. Search as sidebar tab (nested navigator + Android/desktop back)
  2. Auto-hide reader top/bottom bars on chapter change
  3. Horizontal comment preview: chevron steps 1 (phone) / 4 (desktop); mouse drag scroll on desktop
  4. Comment gallery links (relative EH href, close sidebar, correct navigator)
  5. EH/ExHentai search result date seek button (needs source JS support)

Rebuild fully after applying (not hot-reload only).
