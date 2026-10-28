import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/app_page_route.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';

typedef AppLinkCandidate = ({String sourceKey, LinkHandler? linkHandler});
typedef AppLinkTarget = ({String sourceKey, String comicId});

final AppLinks _appLinks = AppLinks();
final List<Uri> _pendingAppLinks = [];
StreamSubscription<Uri>? _appLinkSubscription;
bool _appLinkHandlingReady = false;

/// Starts listening before source initialization so a cold-start link is not
/// lost. Links stay queued until [handleLinks] marks the source registry ready.
void startAppLinkCapture() {
  _appLinkSubscription ??= _appLinks.uriLinkStream.listen(
    (uri) {
      if (!_appLinkHandlingReady) {
        _pendingAppLinks.add(uri);
        return;
      }
      unawaited(_handleCapturedAppLink(uri));
    },
    onError: (Object error, StackTrace stackTrace) {
      Log.error('App Link', error, stackTrace);
    },
  );
}

/// Enables routing after installed comic sources have finished loading.
void handleLinks() {
  startAppLinkCapture();
  _appLinkHandlingReady = true;
  final pending = List<Uri>.from(_pendingAppLinks);
  _pendingAppLinks.clear();
  for (final uri in pending) {
    unawaited(_handleCapturedAppLink(uri));
  }
}

@visibleForTesting
AppLinkTarget? resolveAppLink(Uri uri, Iterable<AppLinkCandidate> candidates) {
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return null;

  for (final candidate in candidates) {
    final handler = candidate.linkHandler;
    if (handler == null ||
        !handler.domains.any((domain) => domain.trim().toLowerCase() == host)) {
      continue;
    }
    try {
      final id = handler.linkToId(uri.toString());
      if (id != null && id.isNotEmpty) {
        return (sourceKey: candidate.sourceKey, comicId: id);
      }
    } catch (e, s) {
      Log.error('App Link', e, s);
    }
  }
  return null;
}

/// Navigator that hosts [ComicPage] routes.
///
/// Comic tiles / details always push onto [App.mainNavigatorKey] (see
/// [ComicTile._onTap]). Prefer that stack so a link opened from a comment
/// sidebar is not pushed onto the Search tab's nested navigator (invisible
/// under the current comic until it is popped).
///
/// Use [NavigatorState.push] via the key's [currentState] — never
/// `Navigator.of(key.currentContext)`, which walks to a *parent* navigator
/// and places the new route under the current comic.
NavigatorState? _navigatorForAppLinks() {
  return App.mainNavigatorKey?.currentState;
}

Future<bool> handleAppLink(Uri uri) async {
  final target = resolveAppLink(
    uri,
    ComicSource.all().map(
      (source) => (sourceKey: source.key, linkHandler: source.linkHandler),
    ),
  );
  if (target == null) return false;

  // Dismiss comment sidebars / dialogs first (they live on the root navigator).
  App.closeRootOverlays();

  // Wait until the overlay routes have actually been removed, then push.
  // A single post-frame callback is not always enough after multiple pops
  // (nested "more comments" sidebars), which caused multi-second delays or
  // the new page staying buried under the current comic.
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(Duration.zero);
  await WidgetsBinding.instance.endOfFrame;

  try {
    final nav = _navigatorForAppLinks();
    if (nav == null) return false;
    await nav.push(
      AppPageRoute(
        builder: (_) => ComicPage(
          id: target.comicId,
          sourceKey: target.sourceKey,
        ),
      ),
    );
    return true;
  } catch (e, s) {
    Log.error('App Link', e, s);
    return false;
  }
}

Future<void> _handleCapturedAppLink(Uri uri) async {
  try {
    await handleAppLink(uri);
  } catch (e, s) {
    Log.error('App Link', e, s);
  }
}
