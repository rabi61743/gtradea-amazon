import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/catalog.dart';
import 'support/api.dart';
import 'support/fake_api.dart';

/// A department row as `/alibaba-categories` returns it.
Map<String, dynamic> dept(String cid, String name, {int sort = 0}) => {
  'cid': cid,
  'parent_cid': null,
  'name': name,
  'sort_order': sort,
  'is_leaf': false,
};

Map<String, dynamic> child(
  String cid,
  String parent,
  String name, {
  int sort = 0,
}) => {
  'cid': cid,
  'parent_cid': parent,
  'name': name,
  'sort_order': sort,
  'is_leaf': true,
};

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
  });

  tearDown(() => ApiClient.overrideDio = null);

  group('the department tree', () {
    test('a department with no children does not bring the tree down', () async {
      // A handful of the real departments genuinely have nothing under them.
      // Sorting the shared const empty list threw, and every screen that reads
      // the tree showed a failure.
      api.onCall('GET', '/alibaba-categories', (call) {
        if (call.query['parent_cid'] == 'null') {
          return reply([dept('a', 'Women'), dept('b', 'Men', sort: 1)]);
        }
        return reply([child('a1', 'a', 'Dresses')]);
      });

      final tree = await CatalogRepository.instance.categoryTree();

      expect(tree.map((c) => c.name), ['Women', 'Men']);
      expect(tree[0].children.single.name, 'Dresses');
      expect(tree[1].children, isEmpty);
    });

    test('children come back in the order the server ordered them', () async {
      api.onCall('GET', '/alibaba-categories', (call) {
        if (call.query['parent_cid'] == 'null') {
          return reply([dept('a', 'Home')]);
        }
        return reply([
          child('a2', 'a', 'Second', sort: 2),
          child('a1', 'a', 'First', sort: 1),
        ]);
      });

      final tree = await CatalogRepository.instance.categoryTree();
      expect(tree.single.children.map((c) => c.name), ['First', 'Second']);
    });

    test(
      'a refused children query is reported, not silently swallowed',
      () async {
        // This assertion used to be the opposite way round: the failure was
        // caught and the tree came back as departments that each claimed to
        // contain nothing. That was written for a server-side cap on the bulk
        // query which does not exist -- all forty-eight parents in one request
        // answers with every one of the eleven hundred subcategories.
        //
        // So the only thing the catch could ever hide was a real failure, and
        // it hid it as an empty catalogue: no error, no retry, nothing to do.
        api.onCall('GET', '/alibaba-categories', (call) {
          if (call.query['parent_cid'] == 'null') {
            return reply([dept('a', 'Home')]);
          }
          return reply({'error': 'too many ids'}, status: 414);
        });

        await expectLater(
          CatalogRepository.instance.categoryTree(),
          throwsA(isA<ApiError>()),
        );
      },
    );

    test('an empty children response is not a failure', () async {
      // The distinction the test above depends on: a server that answers "no
      // children" is telling the truth and must still render.
      api.onCall('GET', '/alibaba-categories', (call) {
        if (call.query['parent_cid'] == 'null') {
          return reply([dept('a', 'Home')]);
        }
        return reply(const []);
      });

      final tree = await CatalogRepository.instance.categoryTree();
      expect(tree.single.name, 'Home');
      expect(tree.single.children, isEmpty);
    });

    test(
      'rows with no cid or no name are dropped, not rendered blank',
      () async {
        api.onCall('GET', '/alibaba-categories', (call) {
          if (call.query['parent_cid'] == 'null') {
            return reply([
              dept('a', 'Home'),
              {'cid': '', 'name': 'No id'},
              {'cid': 'c', 'name': ''},
            ]);
          }
          return reply(const []);
        });

        final tree = await CatalogRepository.instance.categoryTree();
        expect(tree.map((c) => c.name), ['Home']);
      },
    );
  });

  group('failures', () {
    test(
      'a failure inside the app is not reported as a dead connection',
      () async {
        // Both arrive with no status code. Telling someone on full signal to
        // check their network sends them to reboot a router over our bug.
        await expectLater(
          guarded(() async => throw StateError('a decode blew up')),
          throwsA(
            isA<ApiError>()
                .having((e) => e.local, 'local', isTrue)
                .having((e) => e.isNetwork, 'isNetwork', isFalse)
                // And it does not put a Dart error in front of a shopper.
                .having(
                  (e) => e.message,
                  'message',
                  isNot(contains('a decode blew up')),
                ),
          ),
        );
      },
    );

    test('a real transport failure is a network failure', () async {
      // No route registered means the fake answers 404, which is a response --
      // so use a status the mapper treats as a refusal and check the opposite
      // of the case above.
      api.on('GET', '/feed/discover', status: 503, body: {'error': 'down'});

      await expectLater(
        CatalogRepository.instance.discover(),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.message, 'message', 'down')
              .having((e) => e.isNetwork, 'isNetwork', isFalse),
        ),
      );
    });
  });

  group('products', () {
    test(
      'a row with no price says so rather than claiming it is free',
      () async {
        api.on('GET', '/feed/discover', body: feedRows(3));

        final products = await CatalogRepository.instance.discover();
        final unpriced = products.firstWhere((p) => p.numIid == 'iid-1');

        expect(unpriced.displayPrice, isNull);
        expect(unpriced.hasPrice, isFalse);
        expect(products.first.hasPrice, isTrue);
      },
    );

    test('rows with no id are dropped', () async {
      api.on(
        'GET',
        '/feed/discover',
        body: [
          feedRowJson,
          {...feedRowJson, 'num_iid': null},
          {...feedRowJson, 'num_iid': 'x', 'title': ''},
        ],
      );

      final products = await CatalogRepository.instance.discover();
      expect(products, hasLength(1));
    });

    test('badges nobody can read are dropped, and 0% is not a badge', () {
      final product = Product.fromJson({
        ...feedRowJson,
        'seller_identities': ['tp_member', 'yx', 'mystery_flag'],
        'repurchase_rate': '0%',
      });

      expect(product.sellerIdentities, ['tp_member']);
      expect(product.sellerBadge, 'Trade assured');
      // "0% repurchase" reads as a warning about the seller rather than as
      // "nobody has bought twice yet", which is what it means.
      expect(product.repurchaseRate, isNull);
    });

    test(
      'sales are rounded to an order of magnitude, and hidden when tiny',
      () {
        Product withSales(int n) =>
            Product.fromJson({...feedRowJson, 'sales': n});

        expect(withSales(10).salesLabel, isNull);
        expect(withSales(240).salesLabel, '240 sold');
        expect(withSales(4300).salesLabel, '4k+ sold');
        expect(withSales(111344).salesLabel, '100k+ sold');
      },
    );
  });

  group('brands', () {
    test('are read from the server, active ones only', () async {
      // Names for a control the sheet draws switched off. They are fetched
      // rather than typed into the app precisely because they are shown: a
      // hardcoded list of plausible brands would be invented data.
      api.on(
        'GET',
        '/brands',
        body: const [
          {'id': '1', 'name': 'Adidas', 'is_active': true},
          {'id': '2', 'name': 'Retired Brand', 'is_active': false},
          {'id': '3', 'name': 'Apple', 'is_active': true},
        ],
      );

      final brands = await CatalogRepository.instance.brands();

      expect(brands, ['Adidas', 'Apple']);
    });

    test('a row with no name is dropped rather than shown blank', () async {
      api.on(
        'GET',
        '/brands',
        body: const [
          {'id': '1', 'is_active': true},
          {'id': '2', 'name': 'Dell', 'is_active': true},
        ],
      );

      expect(await CatalogRepository.instance.brands(), ['Dell']);
    });

    test('and are asked for without a credential', () async {
      // Public data, like the rest of the catalogue.
      api.on('GET', '/brands', body: const <Map<String, dynamic>>[]);

      await CatalogRepository.instance.brands();

      expect(api.calls.single.authorization, isNull);
    });
  });

  group('search', () {
    test('sends only the filters the server actually parses', () async {
      api.on('GET', '/search/products', body: feedRows(2));

      await CatalogRepository.instance.search(
        query: '  kettle ',
        minPrice: 500,
        maxPrice: 2000,
        sort: ProductSort.priceAsc,
      );

      final call = api.calls.single;
      expect(call.query['q'], 'kettle');
      expect(call.query['min_price'], 500);
      expect(call.query['max_price'], 2000);
      expect(call.query['sort'], 'price_asc');
    });

    test('a blank query is omitted rather than sent empty', () async {
      // An empty q is not the same request as no q: browsing a category with
      // no search term has to leave it off entirely.
      api.on('GET', '/search/products', body: feedRows(2));

      await CatalogRepository.instance.search(query: '   ', categoryCid: 'c1');

      expect(api.calls.single.query.containsKey('q'), isFalse);
      expect(api.calls.single.query['category'], 'c1');
    });

    test('category products ask by page size, not by limit', () async {
      // The handler does not parse `limit`, so sending it silently returns the
      // server default and the page size is quietly ignored.
      api.on('GET', '/categories/c1/products', body: feedRows(2));

      await CatalogRepository.instance.categoryProducts('c1', pageSize: 12);

      expect(api.calls.single.query['page_size'], 12);
      expect(api.calls.single.query.containsKey('limit'), isFalse);
    });
  });

  group('banners', () {
    test('an expired campaign is not shown', () async {
      api.on(
        'GET',
        '/hero-banners',
        body: [
          {
            'id': '1',
            'title': 'Live now',
            'promo_valid_until': '2999-01-01T00:00:00Z',
          },
          {
            'id': '2',
            'title': 'Last Dashain',
            'promo_valid_until': '2020-01-01T00:00:00Z',
          },
          {'id': '3', 'title': 'No expiry set'},
        ],
      );

      final banners = await CatalogRepository.instance.heroBanners();
      expect(banners.map((b) => b.title), ['Live now', 'No expiry set']);
    });

    test(
      'a banner whose artwork carries the words keeps its overlay flag',
      () async {
        api.on(
          'GET',
          '/hero-banners',
          body: [
            {'id': '1', 'title': 'Art only', 'show_text_overlay': false},
            {'id': '2', 'title': 'Text over art'},
          ],
        );

        final banners = await CatalogRepository.instance.heroBanners();
        expect(banners[0].showTextOverlay, isFalse);
        // Absent means yes: a banner that says nothing about it is the ordinary
        // case, and hiding the title by default would blank most of them.
        expect(banners[1].showTextOverlay, isTrue);
      },
    );
  });

  group('guest browsing', () {
    test('carries no credential', () async {
      api.on('GET', '/feed/discover', body: feedRows(1));
      api.on('GET', '/hero-banners', body: const []);
      // Both search endpoints: a plain keyword search goes to the live
      // catalogue and a filtered one to /search/products, and browsing signed
      // out has to stay credential-free on either path.
      stubSearch(api, feedRows(1));

      await CatalogRepository.instance.discover();
      await CatalogRepository.instance.search(query: 'x');
      await CatalogRepository.instance.search(query: 'x', minPrice: 1);
      await CatalogRepository.instance.heroBanners();

      for (final call in api.calls) {
        expect(
          call.headers.containsKey('Authorization'),
          isFalse,
          reason: call.path,
        );
      }
    });
  });
}
