import 'package:gtradea_amazon/core/network/api_client.dart';
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
            'image_url': 'https://example.invalid/child-$i-$c.jpg',
            'sort_order': c,
            'is_leaf': true,
          },
    ]);
  });

  api.on('GET', '/feed/discover', body: feedRows(products));
  api.on('GET', '/feed/trending-products', body: feedRows(products));
  api.on('GET', '/search/products', body: feedRows(products));
  api.on('GET', '/hero-banners', body: const []);

  useStubbedApi(api);
  return api;
}

/// Points the shared client at a fake and clears anything already loaded.
void useStubbedApi(FakeApi api) {
  ApiClient.overrideDio = api.dio();
  CatalogStore.instance.resetForTest();
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
      for (var i = 0; i < count; i++)
        _departmentNames[i % _departmentNames.length],
    ];
