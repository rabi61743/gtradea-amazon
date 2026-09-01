/// What a piece of a written page is.
enum LegalBlockKind {
  /// A section heading. [LegalBlock.level] says how deep -- 1 for the page's
  /// own title row, 2 and 3 for sections under it.
  heading,

  paragraph,

  /// One item of a list, drawn with a bullet.
  bullet,
}

/// One paragraph, heading or bullet of a written page.
class LegalBlock {
  const LegalBlock(this.kind, this.text, {this.level = 0});

  final LegalBlockKind kind;
  final String text;

  /// 1, 2 or 3 for a heading; 0 otherwise.
  final int level;
}

/// Splits a stored page into the blocks it was written as.
///
/// The shop writes its policies in headings, paragraphs and lists -- `h1`,
/// `h2`, `h3`, `p`, `li` -- and the app's [stripHtml] flattens all of it into
/// one run of text, because that is all the checkout sheet needed. A twelve
/// section returns policy read that way is a wall.
///
/// This is deliberately not an HTML renderer. It recognises the handful of
/// tags these pages actually use, keeps their order, and drops everything
/// else. Anything unrecognised degrades to a paragraph rather than
/// disappearing, so a shop that starts using a new tag loses its formatting
/// and not its words.
List<LegalBlock> legalBlocks(String html) {
  if (html.trim().isEmpty) return const [];

  final blocks = <LegalBlock>[];
  // Each match is one element: its tag name, then everything up to the closing
  // tag. Non-greedy, so nested markup inside a paragraph -- <strong>, <a> --
  // stays with the paragraph rather than swallowing the rest of the document.
  final element = RegExp(
    r'<(h1|h2|h3|h4|p|li)\b[^>]*>(.*?)</\1>',
    caseSensitive: false,
    dotAll: true,
  );

  for (final match in element.allMatches(html)) {
    final tag = match.group(1)!.toLowerCase();
    final text = _plain(match.group(2) ?? '');
    if (text.isEmpty) continue;

    blocks.add(switch (tag) {
      'h1' => LegalBlock(LegalBlockKind.heading, text, level: 1),
      'h2' => LegalBlock(LegalBlockKind.heading, text, level: 2),
      'h3' || 'h4' => LegalBlock(LegalBlockKind.heading, text, level: 3),
      'li' => LegalBlock(LegalBlockKind.bullet, text),
      _ => LegalBlock(LegalBlockKind.paragraph, text),
    });
  }

  // A page stored as bare text, or in tags this does not know, still has to be
  // readable -- so it is shown whole rather than as nothing at all.
  if (blocks.isEmpty) {
    final text = _plain(html);
    if (text.isNotEmpty) {
      return [LegalBlock(LegalBlockKind.paragraph, text)];
    }
  }
  return blocks;
}

/// The text of one element, with its inline markup removed.
String _plain(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    // Collapse the newlines the source indentation leaves behind, but keep the
    // ones a <br> asked for.
    .split('\n')
    .map((line) => line.replaceAll(RegExp(r'[ \t\r]+'), ' ').trim())
    .join('\n')
    .trim();
