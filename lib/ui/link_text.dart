import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Splits [text] into plain and URL segments. Matches `http(s)://…` and
/// `www.…` runs; trailing punctuation (`.,;:!?)]}'"`) is trimmed off the
/// URL so "see https://x.io." links cleanly.
/// Trailing characters that are sentence punctuation, not part of a URL.
const _trailingPunct = {
  '.',
  ',',
  ';',
  ':',
  '!',
  '?',
  ')',
  ']',
  '}',
  "'",
  '"',
};

List<LinkSegment> splitLinks(String text) {
  final RegExp pattern = RegExp(r'(https?://[^\s]+|www\.[^\s]+)');
  final List<LinkSegment> out = <LinkSegment>[];
  int cursor = 0;
  for (final RegExpMatch m in pattern.allMatches(text)) {
    int end = m.end;
    while (end > m.start && _trailingPunct.contains(text[end - 1])) {
      end--;
    }
    if (end <= m.start) continue;
    if (m.start > cursor) {
      out.add(LinkSegment(text.substring(cursor, m.start), isLink: false));
    }
    out.add(LinkSegment(text.substring(m.start, end), isLink: true));
    cursor = end;
  }
  if (cursor < text.length) {
    out.add(LinkSegment(text.substring(cursor), isLink: false));
  }
  if (out.isEmpty) out.add(LinkSegment(text, isLink: false));
  return out;
}

class LinkSegment {
  const LinkSegment(this.text, {required this.isLink});
  final String text;
  final bool isLink;
}

/// Task title text with tappable blue URLs. Plain spans inherit
/// [style]; links stay blue + underlined even on completed tasks so a
/// saved URL is always openable. Failures are silent (best-effort).
/// [onLinkTap] fires synchronously on every link tap (used by the task
/// row to suppress its own tap handler via the gesture arena).
class LinkText extends StatelessWidget {
  const LinkText(
    this.text, {
    super.key,
    this.style,
    this.linkColor = Colors.blue,
    this.onLinkTap,
  });

  final String text;
  final TextStyle? style;
  final Color linkColor;
  final VoidCallback? onLinkTap;

  Future<void> _open(String raw) async {
    onLinkTap?.call();
    try {
      final url = raw.startsWith(RegExp(r'https?://', caseSensitive: false))
          ? raw
          : 'https://$raw';
      final uri = Uri.tryParse(url);
      if (uri == null) return;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  Widget build(BuildContext context) {
    // RichText does NOT inherit DefaultTextStyle on its own (unlike Text),
    // so merge explicitly — otherwise a null color renders white.
    final TextStyle base =
        DefaultTextStyle.of(context).style.merge(style);
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          for (final seg in splitLinks(text))
            if (seg.isLink)
              TextSpan(
                text: seg.text,
                style: TextStyle(
                  color: linkColor,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                recognizer: TapGestureRecognizer()..onTap = () => _open(seg.text),
              )
            else
              TextSpan(text: seg.text),
        ],
      ),
    );
  }
}
