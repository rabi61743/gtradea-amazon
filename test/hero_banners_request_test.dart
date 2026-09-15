import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_repository.dart';

import 'support/api.dart';

void main() {
  tearDown(clearApiStub);

  Map<String, dynamic> banner(String id) => {
    'id': id,
    'title': 'Banner $id',
    'background_image_url': 'https://go.gtradea.com/media/banners/$id.png',
    'is_active': true,
  };

  int bannerCalls(dynamic api) => (api.calls as List)
      .where((c) => c.method == 'GET' && c.path == '/hero-banners')
      .length;

  test('callers asking at the same time share one request', () async {
    // The carousel and the flash sale both read the banners on a cold start.
    // They used to send two identical requests.
    final api = stubCatalog()
      ..on('GET', '/hero-banners', body: [banner('a'), banner('b')]);

    final results = await Future.wait([
      CatalogRepository.instance.heroBanners(),
      CatalogRepository.instance.heroBanners(),
    ]);

    expect(bannerCalls(api), 1);
    expect(results[0], hasLength(2));
    expect(identical(results[0], results[1]), isTrue, reason: 'one answer');
  });

  test('a later call asks again rather than reusing an old answer', () async {
    final api = stubCatalog()
      ..on('GET', '/hero-banners', body: [banner('a')]);

    await CatalogRepository.instance.heroBanners();
    await CatalogRepository.instance.heroBanners();

    expect(bannerCalls(api), 2);
  });

  test('a failure reaches every caller, and the next call retries', () async {
    final api = stubCatalog()
      ..on('GET', '/hero-banners', status: 500, body: {'error': 'down'});

    final outcomes = await Future.wait([
      CatalogRepository.instance.heroBanners().then((_) => 'ok', onError: (_) => 'failed'),
      CatalogRepository.instance.heroBanners().then((_) => 'ok', onError: (_) => 'failed'),
    ]);
    expect(outcomes, ['failed', 'failed']);
    expect(bannerCalls(api), 1);

    api.on('GET', '/hero-banners', body: [banner('a')]);
    final retried = await CatalogRepository.instance.heroBanners();
    expect(retried, hasLength(1));
    expect(bannerCalls(api), 2);
  });
}
