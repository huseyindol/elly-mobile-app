import 'package:elly_mobile_app/services/safe_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// DoS limits of the preview sanitizer: [estimatedNestingDepth] must never be below the depth the html package's
/// parser really builds (else hostile nesting slips under [maxPreviewDepth] and parsing takes minutes), and the
/// tag-count cap bounds the work independently.
int _parsedDepth(String html) {
  var max = 0;
  final stack = <(Node, int)>[(html_parser.parse(html), 0)];
  while (stack.isNotEmpty) {
    final (node, depth) = stack.removeLast();
    if (node is Element && depth > max) max = depth;
    for (final child in node.nodes) {
      stack.add((child, node is Element ? depth + 1 : depth));
    }
  }
  return max;
}

/// Repeated units that exploit a naive tag counter (end tags the parser ignores, `/>` on HTML elements, end tags
/// hidden in comments / CDATA / attributes / raw text, foreign-content breakouts).
const _vectors = {
  'unmatched </span>': '<div></span>',
  'unknown </div2>': '<div></div2>',
  'stray </p>': '<div></p>',
  '</br> (parsed as <br>)': '<div></br>',
  'mixed case unmatched': '<DiV></SpAn>',
  'mixed case matched elsewhere': '<SPAN><Div></span>',
  'blocked by a special element': '<span><div></span>',
  'self-closed HTML element': '<div/>',
  'self-closed mixed case': '<DIV />',
  'end tag in a comment': '<div><!--</div>-->',
  'end tag in an abrupt comment': '<div><!--></div>',
  'end tag in a bogus comment': '<div><!</div>',
  'end tag in CDATA (bogus comment in HTML)': '<div><![CDATA[</div>]]>',
  'end tag in a processing instruction': '<div><?</div>',
  'end tag in a quoted attribute': '<div title="</div>">',
  'end tag in a single-quoted attribute': "<div title='</div>'>",
  'end tag in <style> text': '<div><style></div></style>',
  'end tag in <textarea> text': '<div><textarea></div></textarea>',
  'end tag in <title> text': '<div><title></div></title>',
  'end tag in <noscript> text': '<div><noscript></div></noscript>',
  '<script><!-- does not hide what follows': '<script><!--</script><div>',
  'svg breakout then self-closed div': '<svg><div><div/>',
  'svg in foreignObject breakout': '<svg><foreignObject><svg><div>',
  'font with color breaks out': '<svg><font color=red><div/>',
  'table cells': '<table><tr><td><span>',
  'nested lists': '<ul><li><div>',
};

int _startTag(String html) => RegExp('<[a-zA-Z]').allMatches(html).length;

void main() {
  group('estimatedNestingDepth never undercounts the parser', () {
    _vectors.forEach((name, unit) {
      test(name, () {
        final html = List.filled(150, unit).join();
        final estimate = estimatedNestingDepth(html);
        final actual = _parsedDepth(html);
        expect(estimate, greaterThanOrEqualTo(actual - 2), reason: '$name: estimate $estimate < parsed $actual');
      });
    });

    test('a plain e-mail layout is estimated close to reality (no false rejections)', () {
      final rows = List.filled(500, '<tr><td style="padding:8px"><p>Satır <b>kalın</b><br>metin</p></td></tr>').join();
      final html = '<html><body><table width="600"><tbody>$rows</tbody></table></body></html>';
      final estimate = estimatedNestingDepth(html);
      expect(estimate, lessThan(20));
      expect(estimate, greaterThanOrEqualTo(_parsedDepth(html) - 2));
      expect(previewLimitError(html), isNull);
    });
  });

  group('hostile input is rejected or processed in under a second', () {
    _vectors.forEach((name, unit) {
      test(name, () {
        final html = List.filled(20000, unit).join();
        final sw = Stopwatch()..start();
        final out = safePreviewDocument(html);
        expect(sw.elapsedMilliseconds, lessThan(1000), reason: name);
        expect(out, contains(previewCsp));
      });
    });

    test('the reported vector: 20000 × <div></span> (240 KB) is rejected', () {
      final html = List.filled(20000, '<div></span>').join();
      expect(previewLimitError(html), contains('çok karmaşık'));
    });

    test('under the tag cap, the depth estimate alone rejects every nesting vector', () {
      _vectors.forEach((name, unit) {
        if (name == 'end tag in an abrupt comment' || name == 'end tag in <script><!--') return;
        final html = List.filled(maxPreviewDepth + 100, unit).join();
        if (_startTag(html) > maxPreviewTags) return;
        expect(estimatedNestingDepth(html), greaterThan(maxPreviewDepth), reason: name);
        expect(previewLimitError(html), contains('çok karmaşık'), reason: name);
      });
    });

    test('tag-count cap is independent of the depth estimate', () {
      final flat = List.filled(maxPreviewTags + 1, '<br>').join();
      expect(estimatedNestingDepth(flat), 0);
      expect(previewLimitError(flat), contains('çok karmaşık'));
      expect(previewLimitError(List.filled(maxPreviewTags, '<br>').join()), isNull);
    });
  });

  group('sanitizePreviewInBackground (hard time limit)', () {
    test('returns the sanitised document', () async {
      expect(
        await sanitizePreviewInBackground('<p onclick=x>Merhaba</p>'),
        safePreviewDocument('<p onclick=x>Merhaba</p>'),
      );
    });

    test('work over the time limit is abandoned (isolate killed) → null', () async {
      final big = List.filled(9000, '<p>x</p>').join();
      expect(await sanitizePreviewInBackground(big, timeout: const Duration(microseconds: 1)), isNull);
    });
  });
}
