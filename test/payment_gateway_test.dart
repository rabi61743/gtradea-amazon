import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/features/checkout/data/checkout_models.dart';
import 'package:gtradea_amazon/features/checkout/data/payment_gateway.dart';
import 'package:gtradea_amazon/features/checkout/presentation/payment_webview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';
import 'support/orders.dart';

PlacedOrder order(Map<String, dynamic> gateway) => PlacedOrder.fromJson({
  'orderId': 'order-1',
  'orderNumber': 'GT-1001',
  ...gateway,
});

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
  });

  tearDown(() => ApiClient.overrideDio = null);

  group('recognising the return', () {
    test('accepts the configured return host and rejects a lookalike', () {
      // The reference app hardcodes the production host, so a staging build
      // waits forever for a redirect that can never match.
      expect(
        isReturnUrl(Uri.parse('https://gtradea.com/payment/success')),
        isTrue,
      );
      expect(
        isReturnUrl(Uri.parse('https://gtradea.com/payment-callback?x=1')),
        isTrue,
      );

      // A host that merely contains the return host is somebody else's.
      expect(
        isReturnUrl(Uri.parse('https://gtradea.com.evil.test/payment')),
        isFalse,
      );
      expect(isReturnUrl(Uri.parse('https://khalti.com/pay')), isFalse);
      expect(isReturnUrl(Uri.parse('https://gtradea.com/orders')), isFalse);
    });
  });

  group('the auto-submitting form', () {
    test('escapes every key and value', () {
      // These fields are signed by the gateway. A quote breaking out of an
      // attribute would corrupt the bag, and the provider would reject it as a
      // bad signature.
      final html = buildAutoSubmitForm('https://esewa.test/pay', const {
        'signature': 'a"b<c>',
        'total_amount': 1130,
      });

      // The URL survives intact: the default escape mode turns every slash
      // into an entity, which would mangle a signed value the same way.
      expect(html, contains('action="https://esewa.test/pay"'));
      expect(html, contains('name="signature" value="a&quot;b&lt;c&gt;"'));
      expect(html, contains('value="1130"'));
      expect(html, contains('document.forms[0].submit()'));
    });
  });

  group('khalti', () {
    const gateway = KhaltiGateway();

    test('opens the hosted page it was given', () {
      final launch = gateway.launch(
        order({'pidx': 'PIDX1', 'paymentUrl': 'https://khalti.test/pay/PIDX1'}),
      );
      expect(launch.url, 'https://khalti.test/pay/PIDX1');
      expect(launch.actionUrl, isNull);
    });

    test('says so when no page came back rather than opening nothing', () {
      expect(
        () => gateway.launch(order(const {'pidx': 'PIDX1'})),
        throwsA(isA<ApiError>()),
      );
    });

    test(
      'looks up the pidx the gateway returned, not the one it was given',
      () async {
        // Khalti appends the pidx it actually processed. Asking about the
        // original would check the wrong payment.
        api.on(
          'POST',
          '/payments/khalti/lookup',
          body: const {'success': true, 'status': 'success'},
        );

        final verdict = await gateway.confirm(
          order(const {'pidx': 'FROM-INITIATE'}),
          const {'pidx': 'FROM-RETURN'},
        );

        expect(api.calls.single.json['pidx'], 'FROM-RETURN');
        expect(verdict.paid, isTrue);
      },
    );

    test('needs both success and a success status', () async {
      api.on(
        'POST',
        '/payments/khalti/lookup',
        body: const {'success': true, 'status': 'pending'},
      );

      final verdict = await gateway.confirm(order(const {}), const {});
      expect(verdict.paid, isFalse);
    });

    test('a payment under review is terminal, and never offers a retry', () async {
      // The money has been taken and a human is checking it. Retrying takes it
      // twice.
      api.on(
        'POST',
        '/payments/khalti/lookup',
        body: const {'success': true, 'status': 'review'},
      );

      final verdict = await gateway.confirm(order(const {}), const {});
      expect(verdict.paid, isFalse);
      expect(verdict.underReview, isTrue);
    });
  });

  group('esewa', () {
    const gateway = EsewaGateway();

    test('reads the esewaConfig bag the server actually sends', () {
      // Measured against production and confirmed in the storefront's own
      // place-order hook: `submitEsewaPayment(o.esewaConfig, o.actionUrl)`.
      // The app read only `formFields`/`fields`, so a perfectly good signed
      // form arrived and was thrown away as "no form".
      final launch = gateway.launch(
        order(const {
          'esewaConfig': {'signature': 'abc', 'total_amount': '100'},
        }),
      );

      expect(launch.formFields, const {
        'signature': 'abc',
        'total_amount': '100',
      });
    });

    test('posts the signed bag, under either name the server uses', () {
      final withFormFields = gateway.launch(
        order(const {
          'actionUrl': 'https://esewa.test/pay',
          'formFields': {'amt': '100'},
        }),
      );
      expect(withFormFields.formFields, const {'amt': '100'});

      final withFields = gateway.launch(
        order(const {
          'actionUrl': 'https://esewa.test/pay',
          'fields': {'amt': '200'},
        }),
      );
      expect(withFields.formFields, const {'amt': '200'});
    });

    test('falls back to eSewa own form URL when the server names none', () {
      // Measured against production: the initiate call creates the order and
      // returns the signed fields without an actionUrl, and refusing to launch
      // for want of a URL eSewa publishes stranded a good signature. The
      // storefront falls back to the same constant.
      final launch = gateway.launch(
        order(const {
          'formFields': {'signature': 'abc', 'total_amount': '100'},
        }),
      );

      expect(
        launch.actionUrl,
        'https://epay.esewa.com.np/api/epay/main/v2/form',
      );
      expect(launch.formFields, const {
        'signature': 'abc',
        'total_amount': '100',
      });
    });

    test('a server-named endpoint still wins over the fallback', () {
      // A shop pointed at eSewa's test host must not be dragged to production.
      final launch = gateway.launch(
        order(const {
          'actionUrl': 'https://rc-epay.esewa.com.np/api/epay/main/v2/form',
          'formFields': {'signature': 'abc'},
        }),
      );

      expect(launch.actionUrl, startsWith('https://rc-epay.esewa.com.np'));
    });

    test('no fields at all is still reported as a missing form', () {
      // The signature is the part only the server can produce. Without it
      // there is nothing to post, and a default URL cannot help.
      expect(() => gateway.launch(order(const {})), throwsA(isA<ApiError>()));
    });

    test('sends the base64 envelope back verbatim', () async {
      api.on('POST', '/payments/esewa/verify', body: const {'success': true});

      final verdict = await gateway.confirm(order(const {}), const {
        'data': 'eyJhIjoxfQ==',
      });

      expect(api.calls.single.json['data'], 'eyJhIjoxfQ==');
      expect(verdict.paid, isTrue);
    });

    test('needs only success, because its verify carries no status', () async {
      // Requiring a status here would reject every good eSewa payment.
      api.on(
        'POST',
        '/payments/esewa/verify',
        body: const {'success': true, 'status': null},
      );

      final verdict = await gateway.confirm(order(const {}), const {
        'data': 'x',
      });
      expect(verdict.paid, isTrue);
    });

    test('a return with no envelope is a cancellation, not an error', () async {
      // eSewa attaches the envelope to its success URL only. Coming back
      // without one is the failure URL -- the shopper cancelled, or it did not
      // go through. Nothing is sent, because there is nothing to verify.
      final verdict = await gateway.confirm(order(const {}), const {});

      expect(verdict.paid, isFalse);
      expect(
        verdict.abandoned,
        isTrue,
        reason: 'nothing was charged, and a retry must still be offered',
      );
      expect(api.calls, isEmpty);
    });

    test('has no direct probe, so the order poll is the fallback', () {
      expect(gateway.poll(order(const {})), isNull);
    });
  });

  group('connectips', () {
    const gateway = ConnectIpsGateway();

    test('posts the bag under its own key', () {
      final launch = gateway.launch(
        order(const {
          'actionUrl': 'https://connectips.test/pay',
          'connectipsConfig': {'TXNID': 'T1'},
        }),
      );
      expect(launch.formFields, const {'TXNID': 'T1'});
    });

    test('prefers the txnId it was given over the one returned', () async {
      // connectIPS returns to a static URL and may append nothing at all, so
      // the initiate value is the reliable one.
      api.on(
        'POST',
        '/payments/connectips/check-status',
        body: const {'success': true, 'status': 'success'},
      );

      await gateway.confirm(order(const {'txnId': 'FROM-INITIATE'}), const {
        'TXNID': 'FROM-RETURN',
      });

      expect(api.calls.single.json['txnId'], 'FROM-INITIATE');
    });

    test('falls back to the returned txnId when it was given none', () async {
      api.on(
        'POST',
        '/payments/connectips/check-status',
        body: const {'success': true, 'status': 'success'},
      );

      await gateway.confirm(order(const {}), const {'TXNID': 'FROM-RETURN'});
      expect(api.calls.single.json['txnId'], 'FROM-RETURN');
    });
  });

  group('nps', () {
    const gateway = NpsGateway();

    final nps = order(const {
      'gatewayConfig': {
        'actionUrl': 'https://nps.test/pay',
        'fields': {'MerchantTxnId': 'M1', 'Amount': '100'},
      },
    });

    test('reads the nested action and fields', () {
      final launch = gateway.launch(nps);
      expect(launch.actionUrl, 'https://nps.test/pay');
      expect(launch.formFields?['MerchantTxnId'], 'M1');
    });

    test('lifts the merchant transaction id out of the signed bag', () async {
      api.on(
        'POST',
        '/payments/nps/check-status',
        body: const {'success': true, 'status': 'success'},
      );

      await gateway.confirm(nps, const {'GatewayTxnId': 'G1'});

      expect(api.calls.single.json['merchantTxnId'], 'M1');
      expect(api.calls.single.json['gatewayTxnId'], 'G1');
    });

    test('omits the gateway transaction id rather than sending null', () async {
      api.on(
        'POST',
        '/payments/nps/check-status',
        body: const {'success': true, 'status': 'success'},
      );

      await gateway.confirm(nps, const {});

      expect(api.calls.single.json.containsKey('gatewayTxnId'), isFalse);
    });

    test('a customer who never started is a back-out, not a failure', () async {
      // NPS is the only provider that can tell the difference, and reporting
      // "payment failed" to someone who simply closed the page is wrong.
      api.on(
        'POST',
        '/payments/nps/check-status',
        body: const {'success': false, 'started': false},
      );

      final verdict = await gateway.confirm(nps, const {});
      expect(verdict.paid, isFalse);
      expect(verdict.abandoned, isTrue);
    });

    test('a started payment that failed is a failure', () async {
      api.on(
        'POST',
        '/payments/nps/check-status',
        body: const {'success': false, 'status': 'failed', 'started': true},
      );

      final verdict = await gateway.confirm(nps, const {});
      expect(verdict.abandoned, isFalse);
      expect(verdict.paid, isFalse);
    });
  });

  group('fonepay', () {
    const gateway = FonepayGateway();

    test('sends the whole return map back untouched', () async {
      // A DV signature covers every parameter, so dropping or renaming one
      // invalidates it.
      api.on(
        'POST',
        '/payments/fonepay/verify',
        body: const {'success': true, 'status': 'success'},
      );

      await gateway.confirm(order(const {}), const {
        'PRN': 'P1',
        'BID': 'B1',
        'UID': 'U1',
        'DV': 'signature',
      });

      final sent = api.calls.single.json;
      expect(sent['PRN'], 'P1');
      expect(sent['BID'], 'B1');
      expect(sent['UID'], 'U1');
      expect(sent['DV'], 'signature');
    });

    test('adds the uppercase alias when the gateway sent lowercase', () async {
      api.on(
        'POST',
        '/payments/fonepay/verify',
        body: const {'success': true, 'status': 'success'},
      );

      await gateway.confirm(order(const {}), const {'prn': 'P1'});

      final sent = api.calls.single.json;
      expect(sent['PRN'], 'P1');
      expect(sent['prn'], 'P1', reason: 'the original is left in place');
    });

    test('anything that is not an explicit failure counts as paid', () async {
      // Fonepay reports success with a status this app has no list of, so the
      // test is negative.
      api.on(
        'POST',
        '/payments/fonepay/verify',
        body: const {'success': true, 'status': 'somethingelse'},
      );
      expect((await gateway.confirm(order(const {}), const {})).paid, isTrue);

      api.on(
        'POST',
        '/payments/fonepay/verify',
        body: const {'success': true, 'status': 'failed'},
      );
      expect((await gateway.confirm(order(const {}), const {})).paid, isFalse);
    });
  });

  group('the order poll', () {
    test(
      'reads paid, failed and still-waiting from the order itself',
      () async {
        Future<GatewayVerdict> withOrder(String status, String payment) {
          api.on(
            'GET',
            '/orders/order-1',
            body: orderJson(status: status, paymentStatus: payment),
          );
          return pollOrderPayment('order-1');
        }

        expect((await withOrder('processing', 'paid')).paid, isTrue);
        expect((await withOrder('processing', 'completed')).paid, isTrue);
        expect((await withOrder('processing', 'failed')).status, 'failed');
        expect((await withOrder('cancelled', 'pending')).status, 'failed');
        // Neither paid nor refused: the screen keeps waiting rather than
        // declaring a failure while a bank is still processing.
        expect((await withOrder('processing', 'pending')).status, 'pending');
      },
    );

    test('an order with no id is refused rather than fetched', () async {
      await expectLater(pollOrderPayment(''), throwsA(isA<ApiError>()));
      expect(api.calls, isEmpty);
    });
  });
}
