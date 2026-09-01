import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/realtime/realtime_service.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';

import 'catalog.dart';
import 'fake_api.dart';

/// Puts a stand-in catalogue behind the whole app.
///
/// Widget tests drive real screens, and those screens now fetch. Stubbing at
/// the HTTP layer rather than at the repository means the tests still exercise
/// the decoding, the error mapping and the cache -- everything except the
/// socket.
FakeApi stubCatalog({
  int departments = 7,
  int childrenEach = 3,
  int products = 6,

  /// False serves subcategories with no artwork, which the real catalogue does
  /// for a few of them. The tiles must still render.
  bool childImages = true,
}) {
  final api = FakeApi();

  api.onCall('GET', '/alibaba-categories', (call) {
    // One path, two very different questions: the top level, then every child
    // of every top-level department in one go.
    if (call.query['parent_cid'] == 'null') {
      return reply([
        for (var i = 0; i < departments; i++)
          {
            'cid': 'dept-$i',
            'parent_cid': null,
            'name': _departmentNames[i % _departmentNames.length],
            'image_url': 'https://example.invalid/dept-$i.jpg',
            'sort_order': i,
            'is_leaf': false,
          },
      ]);
    }
    return reply([
      for (var i = 0; i < departments; i++)
        for (var c = 0; c < childrenEach; c++)
          {
            'cid': 'dept-$i-child-$c',
            'parent_cid': 'dept-$i',
            'name': '${_departmentNames[i % _departmentNames.length]} item $c',
            'image_url': childImages
                ? 'https://example.invalid/child-$i-$c.jpg'
                : null,
            'sort_order': c,
            'is_leaf': true,
          },
    ]);
  });

  // Signing in makes the app fetch the account's cart, so every stub needs a
  // cart even when the test is about something else.
  api.on('GET', '/cart', body: const {'items': [], 'subtotal': 0});
  api.on('DELETE', '/cart', status: 204);

  api.on('GET', '/feed/discover', body: feedRows(products));
  api.on('GET', '/feed/trending-products', body: feedRows(products));
  api.on('GET', '/search/products', body: feedRows(products));
  // A plain keyword search goes to the live 1688 catalogue instead, because
  // that one ranks by keyword and /search/products does not. Same rows, and
  // wrapped in the envelope that endpoint actually returns.
  api.on('GET', '/api/1688/search', body: {'items': feedRows(products)});
  api.on('GET', '/hero-banners', body: const []);

  useStubbedApi(api);
  return api;
}

/// The two endpoints a product search can go to.
///
/// A plain keyword search goes to the live 1688 catalogue, which ranks by
/// keyword; anything with a filter or a chosen sort goes to `/search/products`,
/// which is the only one that honours them. A test asserting on "the search
/// that went out" should not have to care which, so it asks for both.
const kSearchPaths = ['/search/products', '/api/1688/search'];

bool isSearchCall(RecordedCall call) => kSearchPaths.contains(call.path);

/// Answers both search endpoints with the same rows.
///
/// Stubbing only one leaves the other on the default stub, so a test meaning
/// "search finds nothing" gets six products from whichever endpoint it forgot --
/// and passes or fails for a reason that has nothing to do with what it is
/// about.
void stubSearch(FakeApi api, List<Map<String, dynamic>> rows, {int? status}) {
  api.on('GET', '/search/products', body: rows, status: status ?? 200);
  api.on(
    'GET',
    '/api/1688/search',
    body: {'items': rows},
    status: status ?? 200,
  );
}

/// The same, for a search whose answer depends on what was asked.
void stubSearchWith(
  FakeApi api,
  List<Map<String, dynamic>> Function(RecordedCall) rows,
) {
  api.onCall('GET', '/search/products', (call) => reply(rows(call)));
  api.onCall('GET', '/api/1688/search', (call) => reply({'items': rows(call)}));
}

/// Points the shared client at a fake and clears anything already loaded.
void useStubbedApi(FakeApi api) {
  // No gateway to open a socket to in a test.
  RealtimeService.enabled = false;
  _installed = api;
  ApiClient.overrideDio = api.dio();
  CatalogStore.instance.resetForTest();
}

FakeApi? _installed;

/// The stub currently behind the app, installing a default if there is none.
///
/// Signing in now reaches the gateway, so a test that only meant to check a
/// label would otherwise fire a real request.
FakeApi ensureApiStub() => _installed ?? stubCatalog();

void clearApiStub() {
  _installed = null;
  ApiClient.overrideDio = null;
}

const _departmentNames = [
  'Women',
  'Men',
  'Electronics',
  'Home and kitchen',
  'Sports and outdoors',
  'Beauty and care',
  'Toys and baby',
  'Tools and hardware',
];

/// The department names the stub serves, in order. Index-based assertions in
/// the browse tests key on this rather than on a copy of it.
List<String> stubDepartmentNames(int count) => [
  for (var i = 0; i < count; i++) _departmentNames[i % _departmentNames.length],
];
