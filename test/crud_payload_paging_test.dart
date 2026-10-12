import 'package:elly_mobile_app/services/crud_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pagedEndpoint', () {
    test('adds page/size to a bare path', () {
      expect(Uri.parse(pagedEndpoint('/posts/list/paged', 0, 20)).queryParameters, {'page': '0', 'size': '20'});
    });

    test('keeps existing params and overrides page/size', () {
      final uri = Uri.parse(pagedEndpoint('/assets/list/paged?sort=id,desc&page=9', 2, 10));
      expect(uri.path, '/assets/list/paged');
      expect(uri.queryParameters, {'sort': 'id,desc', 'page': '2', 'size': '10'});
    });

    test('overrides an existing size and keeps unrelated params untouched', () {
      final uri = Uri.parse(pagedEndpoint('/posts/list/paged?size=5&status=ACTIVE', 3, 50));
      expect(uri.queryParameters, {'size': '50', 'status': 'ACTIVE', 'page': '3'});
    });

    test('empty query string (trailing "?") is treated as no query', () {
      final uri = Uri.parse(pagedEndpoint('/posts/list/paged?', 1, 20));
      expect(uri.path, '/posts/list/paged');
      expect(uri.queryParameters, {'page': '1', 'size': '20'});
    });

    test('result stays relative (no scheme/host added) and keeps the path', () {
      final uri = Uri.parse(pagedEndpoint('/assets/list/paged?sort=id,desc', 0, 20));
      expect(uri.hasScheme, isFalse);
      expect(uri.hasAuthority, isFalse);
      expect(pagedEndpoint('/assets/list/paged', 0, 20), startsWith('/assets/list/paged?'));
    });

    test('values with reserved characters round-trip encoded', () {
      final uri = Uri.parse(pagedEndpoint('/x/list/paged?q=a%20b%26c', 0, 20));
      expect(uri.queryParameters['q'], 'a b&c');
    });

    test(
      'a repeated param (Spring multi-sort) is not collapsed',
      () {
        final uri = Uri.parse(pagedEndpoint('/x/list/paged?sort=id,desc&sort=name,asc', 0, 20));
        expect(uri.queryParametersAll['sort'], ['id,desc', 'name,asc']);
      },
    );
  });

  group('isLastPage', () {
    test('uses PagedResponse.last when present', () {
      expect(
        isLastPage({
          'content': [1, 2],
          'last': true,
        }, 2),
        isTrue,
      );
      expect(
        isLastPage({
          'content': [1],
          'last': false,
        }, 2),
        isFalse,
      );
    });

    test('falls back to a short page', () {
      expect(
        isLastPage({
          'content': [
            {'id': 1},
          ],
        }, 2),
        isTrue,
      );
      expect(
        isLastPage({
          'content': [
            {'id': 1},
            {'id': 2},
          ],
        }, 2),
        isFalse,
      );
    });

    test('a plain list is a single page', () {
      expect(isLastPage([1, 2, 3], 2), isTrue);
    });

    test('last wins over the item count in both directions', () {
      // Full page flagged last (total is an exact multiple of size).
      expect(
        isLastPage({
          'content': [1, 2],
          'last': true,
        }, 2),
        isTrue,
      );
      // Short page flagged not-last (server-side filtering): trust the server.
      expect(
        isLastPage({
          'content': [1],
          'last': false,
        }, 2),
        isFalse,
      );
    });

    test('Spring Page fields other than last are ignored (only PagedResponse.last counts)', () {
      expect(
        isLastPage({
          'content': [
            {'id': 1},
            {'id': 2},
          ],
          'totalPages': 1,
          'number': 0,
        }, 2),
        isFalse,
      );
    });

    test('explicit null last falls back to the item count', () {
      expect(
        isLastPage({
          'content': [
            {'id': 1},
          ],
          'last': null,
        }, 2),
        isTrue,
      );
      expect(
        isLastPage({
          'content': [
            {'id': 1},
            {'id': 2},
          ],
          'last': null,
        }, 2),
        isFalse,
      );
    });

    test('missing/empty content without last is the last page', () {
      expect(isLastPage(<String, dynamic>{}, 20), isTrue);
      expect(isLastPage({'content': []}, 20), isTrue);
      expect(isLastPage({'content': null}, 20), isTrue);
    });

    test('non-collection data (null, scalar) is treated as the last page', () {
      expect(isLastPage(null, 20), isTrue);
      expect(isLastPage('oops', 20), isTrue);
      expect(isLastPage(<dynamic>[], 20), isTrue);
    });

    test('non-map content entries do not count towards a full page', () {
      expect(
        isLastPage({
          'content': [1, 'x', null],
        }, 2),
        isTrue,
      );
    });
  });

  group('totalCount', () {
    test('list → length', () => expect(totalCount([1, 2, 3]), 3));
    test('page → totalElements', () => expect(totalCount({'content': [], 'totalElements': 1234}), 1234));
    test('page without totalElements → content length', () {
      expect(
        totalCount({
          'content': [
            {'id': 1},
            {'id': 2},
          ],
        }),
        2,
      );
    });
    test('unknown shape → null', () => expect(totalCount(null), isNull));
    test('scalar → null', () => expect(totalCount('x'), isNull));
    test('empty list → 0', () => expect(totalCount(<dynamic>[]), 0));
    test('totalElements 0 is respected, not replaced by the content length', () {
      expect(
        totalCount({
          'content': [
            {'id': 1},
          ],
          'totalElements': 0,
        }),
        0,
      );
    });
    test('totalElements wins over the loaded page size', () {
      expect(
        totalCount({
          'content': [
            {'id': 1},
          ],
          'totalElements': 57,
        }),
        57,
      );
    });
    test('totalElements sent as a JSON double is truncated to int', () {
      expect(totalCount({'content': [], 'totalElements': 12.0}), 12);
    });
    test('empty map → 0 (no content, no totalElements)', () => expect(totalCount(<String, dynamic>{}), 0));
    test('explicit null totalElements falls back to content length', () {
      expect(
        totalCount({
          'content': [
            {'id': 1},
          ],
          'totalElements': null,
        }),
        1,
      );
    });
  });
}
