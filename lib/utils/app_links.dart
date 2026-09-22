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

/// Navigator that currently hosts comic detail routes.
///
/// Do NOT use [GlobalKey.currentContext] + [Navigator.of]: that context belongs
/// to the [Navigator] element and [Navigator.of] walks to a *parent* navigator,
/// so the new page is pushed under the current comic (only visible after pop).
NavigatorState? _navigatorForAppLinks() {
  if (App.secondaryNavigatorActive) {
    final secondary = App.secondaryNavigatorKey?.currentState;
    if (secondary != null) return secondary;
  }
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

  // Dismiss comment sidebars / dialogs first.
  App.closeRootOverlays();

  // Push on the next frame so pops are applied before the new route.
  final completer = Completer<bool>();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      final nav = _navigatorForAppLinks();
      if (nav == null) {
        completer.complete(false);
        return;
      }
      nav.push(
        AppPageRoute(
          builder: (_) => ComicPage(
            id: target.comicId,
            sourceKey: target.sourceKey,
          ),
        ),
      );
      completer.complete(true);
    } catch (e, s) {
      Log.error('App Link', e, s);
      completer.complete(false);
    }
  });
  return completer.future;
}

Future<void> _handleCapturedAppLink(Uri uri) async {
  try {
    await handleAppLink(uri);
  } catch (e, s) {
    Log.error('App Link', e, s);
  }
}
