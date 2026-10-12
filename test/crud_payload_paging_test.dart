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
  });
}
