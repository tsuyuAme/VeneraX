import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/image_provider/cached_image.dart';
import 'package:venera/utils/app_links.dart';
import 'package:venera/utils/ext.dart';

/// The user-configured font size for comment body & user name text.
/// Falls back to the framework default when unset.
double get commentsFontSize {
  final v = appdata.settings['commentsFontSize'];
  if (v is num) return v.toDouble();
  return 14.0;
}

/// A widget that displays comment content with support for rich text formatting.
///
/// This widget intelligently decides whether to use simple text or rich formatting
/// based on the content. It supports HTML tags and auto-linking of URLs.
class CommentContent extends StatelessWidget {
  const CommentContent({super.key, required this.text, this.fontSize});

  final String text;

  /// Explicit font size for the comment body. When null, inherits the ambient
  /// [DefaultTextStyle] (used by compact previews that must not scale).
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    if (!text.contains('<') && !text.contains('http')) {
      return SelectableText(text, style: fontSize == null ? null : TextStyle(fontSize: fontSize));
    } else {
      return RichCommentContent(text: text, fontSize: fontSize);
    }
  }
}

class _Tag {
  final String name;
  final Map<String, String> attributes;

  const _Tag(this.name, this.attributes);

  TextSpan merge(TextSpan s, BuildContext context) {
    var style = s.style ?? ts;
    style = switch (name) {
      'b' => style.bold,
      'i' => style.italic,
      'u' => style.underline,
      's' => style.lineThrough,
      'a' => style.withColor(context.colorScheme.primary),
      'strong' => style.bold,
      'span' => () {
        if (attributes.containsKey('style')) {
          var s = attributes['style']!;
          var css = s.split(';');
          for (var c in css) {
            var kv = c.split(':');
            if (kv.length == 2) {
              var key = kv[0].trim();
              var value = kv[1].trim();
              switch (key) {
                case 'color':
                  // Color is not supported, we should make text display well in light and dark mode.
                  break;
                case 'font-weight':
                  if (value == 'bold') {
                    style = style.bold;
                  } else if (value == 'lighter') {
                    style = style.light;
                  }
                  break;
                case 'font-style':
                  if (value == 'italic') {
                    style = style.italic;
                  }
                  break;
                case 'text-decoration':
                  if (value == 'underline') {
                    style = style.underline;
                  } else if (value == 'line-through') {
                    style = style.lineThrough;
                  }
                  break;
                case 'font-size':
                  // Font size is not supported.
                  break;
              }
            }
          }
        }
        return style;
      }(),
      _ => style,
    };
    if (style.color != null) {
      style = style.copyWith(decorationColor: style.color);
    }
    var recognizer = s.recognizer;
    if (name == 'a') {
      final link = resolveHref(attributes['href']);
      if (link != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () {
            handleLink(link);
          };
      }
    }
    return TextSpan(text: s.text, style: style, recognizer: recognizer);
  }

  /// EH-style relative / protocol-relative hrefs → absolute https URLs.
  static String? resolveHref(String? href) {
    if (href == null) return null;
    var link = href.trim();
    if (link.isEmpty ||
        link.startsWith('#') ||
        link.toLowerCase().startsWith('javascript:')) {
      return null;
    }
    if (link.startsWith('//')) {
      link = 'https:$link';
    } else if (link.startsWith('/')) {
      link = 'https://exhentai.org$link';
    }
    if (link.isURL) return link;
    if (RegExp(
      r'^https?://(e-|ex)hentai\.org/',
      caseSensitive: false,
    ).hasMatch(link)) {
      return link;
    }
    return null;
  }

  static void handleLink(String link) async {
    final resolved = resolveHref(link) ?? (link.isURL ? link : null);
    if (resolved == null) return;
    final uri = Uri.tryParse(resolved);
    if (uri == null) return;
    // handleAppLink closes root overlays (comment sidebars) and pushes onto
    // the same navigator as normal comic tiles. Do not close overlays here
    // as well — a double-pop can dismiss the comic page itself.
    if (await handleAppLink(uri)) {
      return;
    }
    // External / unmatched URL: still dismiss sidebars before leaving the app.
    App.closeRootOverlays();
    try {
      await launchUrlString(resolved);
    } catch (_) {}
  }
}

class _CommentImage {
  final String url;
  final String? link;

  const _CommentImage(this.url, this.link);
}

class RichCommentContent extends StatefulWidget {
  const RichCommentContent({
    super.key,
    required this.text,
    this.showImages = true,
    this.fontSize,
    this.selectable = true,
  });

  final String text;

  final bool showImages;

  /// Explicit font size for the comment body. When null, inherits the ambient
  /// [DefaultTextStyle] (used by compact previews that must not scale).
  final double? fontSize;

  /// Prefer false inside horizontal lists so link taps are not stolen.
  final bool selectable;

  @override
  State<RichCommentContent> createState() => _RichCommentContentState();
}

class _RichCommentContentState extends State<RichCommentContent> {
  var textSpan = <InlineSpan>[];
  var images = <_CommentImage>[];
  bool isRendered = false;

  @override
  void didChangeDependencies() {
    if (!isRendered) {
      render();
      isRendered = true;
    }
    super.didChangeDependencies();
  }

  bool isValidUrlChar(String char) {
    return RegExp(r'[a-zA-Z0-9%:/.@\-_?&=#*!+;]').hasMatch(char);
  }

  void render() {
    var s = Queue<_Tag>();

    int i = 0;
    var buffer = StringBuffer();
    var text = widget.text;
    text = text.replaceAll('\r\n', '\n');
    text = text.replaceAll('&amp;', '&');

    void writeBuffer() {
      if (buffer.isEmpty) return;
      var span = TextSpan(text: buffer.toString());
      for (var tag in s) {
        span = tag.merge(span, context);
      }
      textSpan.add(span);
      buffer.clear();
    }

    while (i < text.length) {
      if (text[i] == '<' && i != text.length - 1) {
        if (text[i + 1] != '/') {
          // start tag
          var j = text.indexOf('>', i);
          if (j != -1) {
            var tagContent = text.substring(i + 1, j);
            var splits = tagContent.split(' ');
            splits.removeWhere((element) => element.isEmpty);
            var tagName = splits[0];
            var attributes = <String, String>{};
            for (var k = 1; k < splits.length; k++) {
              var attr = splits[k];
              var attrSplits = attr.split('=');
              if (attrSplits.length == 2) {
                attributes[attrSplits[0]] = attrSplits[1].replaceAll('"', '');
              }
            }
            const acceptedTags = [
              'img',
              'a',
              'b',
              'i',
              'u',
              's',
              'br',
              'span',
              'strong',
            ];
            if (acceptedTags.contains(tagName)) {
              writeBuffer();
              if (tagName == 'img') {
                var url = attributes['src'];
                String? link;
                for (var tag in s) {
                  if (tag.name == 'a') {
                    link = tag.attributes['href'];
                    break;
                  }
                }
                if (url != null) {
                  images.add(_CommentImage(url, link));
                }
              } else if (tagName == 'br') {
                buffer.write('\n');
              } else {
                s.add(_Tag(tagName, attributes));
              }
              i = j + 1;
              continue;
            }
          }
        } else {
          // end tag
          var j = text.indexOf('>', i);
          if (j != -1) {
            var tagContent = text.substring(i + 2, j);
            var splits = tagContent.split(' ');
            splits.removeWhere((element) => element.isEmpty);
            var tagName = splits[0];
            if (s.isNotEmpty && s.last.name == tagName) {
              writeBuffer();
              s.removeLast();
              i = j + 1;
              continue;
            }
            if (tagName == 'br') {
              i = j + 1;
              buffer.write('\n');
              continue;
            }
          }
        }
      } else if (text.length - i > 8 &&
          text.substring(i, i + 4) == 'http' &&
          !s.any((e) => e.name == 'a')) {
        // auto link
        int j = i;
        for (; j < text.length; j++) {
          if (!isValidUrlChar(text[j])) {
            break;
          }
        }
        var url = text.substring(i, j);
        if (url.isURL) {
          writeBuffer();
          textSpan.add(
            TextSpan(
              text: url,
              style: ts.withColor(context.colorScheme.primary),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  _Tag.handleLink(url);
                },
            ),
          );
          i = j;
          continue;
        }
      }
      buffer.write(text[i]);
      i++;
    }
    writeBuffer();
  }

  @override
  Widget build(BuildContext context) {
    var baseStyle = DefaultTextStyle.of(context).style;
    if (widget.fontSize != null) {
      baseStyle = baseStyle.copyWith(fontSize: widget.fontSize);
    }
    final span = TextSpan(style: baseStyle, children: textSpan);
    Widget content = widget.selectable
        ? SelectableText.rich(span)
        : Text.rich(span);
    if (images.isNotEmpty && widget.showImages) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          Wrap(
            runSpacing: 4,
            spacing: 4,
            children: images.map((e) {
              final size = widget.selectable ? 100.0 : 72.0;
              Widget image = Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
                width: size,
                height: size,
                clipBehavior: Clip.antiAlias,
                child: Image(
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  image: CachedImageProvider(e.url),
                ),
              );
              // Prefer explicit <a href>, else try opening the image URL itself
              // when it is a gallery/cover host page (rare).
              final tapLink = e.link ??
                  (e.url.isURL && e.url.contains('hentai.org/g/')
                      ? e.url
                      : null);
              if (tapLink != null) {
                image = Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _Tag.handleLink(tapLink);
                    },
                    child: image,
                  ),
                );
              }
              return image;
            }).toList(),
          ),
        ],
      );
    }
    return content;
  }
}
