import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';
import '../../orders/data/orders_repository.dart';
import 'checkout_models.dart';
import 'checkout_repository.dart';
import 'payment_method.dart';

/// What a provider needs opened in the WebView.
///
/// Either a page to visit or a form to post -- never both, and every provider
/// does exactly one of the two.
class GatewayLaunch {
  const GatewayLaunch.redirect(this.url) : actionUrl = null, formFields = null;

  const GatewayLaunch.form(String this.actionUrl, Map<String, dynamic> fields)
    : url = null,
      formFields = fields;

  final String? url;
  final String? actionUrl;
  final Map<String, dynamic>? formFields;
}

/// What the provider said after the shopper came back.
class GatewayVerdict {
  const GatewayVerdict({
    required this.paid,
    this.status,
    this.message,
    this.abandoned = false,
  });

  final bool paid;

  /// The provider's own word for it. Kept because two of them carry meaning
  /// beyond paid/not-paid.
  final String? status;

  final String? message;

  /// True when the shopper reached the gateway and left without paying, as
  /// distinct from a payment that was attempted and refused. Only NPS reports
  /// this, and only it can tell the difference.
  final bool abandoned;

  /// Money has been taken and a human is checking it before release.
  ///
  /// Khalti only. Terminal: retrying would take the money twice, so the screen
  /// must not offer it.
  bool get underReview => status == 'review';
}

/// One provider's half of the handshake.
///
/// A class per provider rather than one parameterised function. The four
/// differ in what they return, what they send back, and what counts as paid --
/// and every attempt to unify them loses one of those differences quietly.
abstract class PaymentGateway {
  const PaymentGateway();

  /// The gateway path segment, e.g. `khalti`.
  String get id;

  /// What to open, from the initiate response. Throws [ApiError] when the
  /// provider did not return anything openable.
  GatewayLaunch launch(PlacedOrder order);

  /// Confirms with the server, using the parameters the return URL carried.
  Future<GatewayVerdict> confirm(
    PlacedOrder order,
    Map<String, String> returned,
  );

  /// Confirms without a return URL, for when the shopper never came back
  /// through the WebView. Null when this provider has no server-to-server
  /// probe and the order poll is the only option.
  Future<GatewayVerdict> Function()? poll(PlacedOrder order) => null;

  static const _all = <PaymentGateway>[
    KhaltiGateway(),
    EsewaGateway(),
    ConnectIpsGateway(),
    NpsGateway(),
    FonepayGateway(),
  ];

  /// The gateway for a method id, or null when the method needs no handshake
  /// (cash on delivery) or is not implemented here.
  static PaymentGateway? forId(String id) {
    for (final gateway in _all) {
      if (gateway.id == id) return gateway;
    }
    return null;
  }

  /// Whether the app can actually carry this method through to a payment.
  ///
  /// The shop switches methods on for the website, which has a handshake for
  /// several this app does not -- `fonepayintent` today. Offering one means a
  /// shopper picks it, agrees a total, taps Pay, and is only then told it does
  /// not work here. Cash on delivery needs no gateway and is always drivable.
  static bool canComplete(String id) =>
      forId(id) != null || PaymentKind.of(id) == PaymentKind.cashOnDelivery;

  /// Reads a field from the initiate response.
  static String? _str(PlacedOrder order, String key) =>
      asString(order.gateway[key]);

  static Never _missing(String what) => throw ApiError(
    statusCode: null,
    message: 'The payment provider did not return $what.',
  );
}

/// Asks the order itself whether it has been paid.
///
/// The fallback for eSewa and Fonepay, which cannot be probed directly: their
/// verify calls need parameters that only exist in a return URL the shopper
/// never came back through. It works for any provider because the same server
/// path that settles an order on verify also settles it when the gateway's
/// webhook lands.
Future<GatewayVerdict> pollOrderPayment(String orderId) async {
  if (orderId.isEmpty) {
    throw const ApiError(
      statusCode: null,
      message: 'There is no order to check.',
    );
  }

  final order = await OrdersRepository.instance.byId(orderId);

  if (order.isPaid) {
    return const GatewayVerdict(paid: true, status: 'success');
  }
  if (order.paymentFailed || order.isCancelled) {
    return const GatewayVerdict(paid: false, status: 'failed');
  }
  // Still in flight. Neither paid nor refused, which is the whole reason this
  // screen keeps waiting rather than reporting.
  return const GatewayVerdict(paid: false, status: 'pending');
}

/// Khalti: a hosted page, correlated by `pidx`.
class KhaltiGateway extends PaymentGateway {
  const KhaltiGateway();

  @override
  String get id => 'khalti';

  @override
  GatewayLaunch launch(PlacedOrder order) {
    final url = PaymentGateway._str(order, 'paymentUrl');
    if (url == null) PaymentGateway._missing('a payment page');
    return GatewayLaunch.redirect(url);
  }

  @override
  Future<GatewayVerdict> confirm(
    PlacedOrder order,
    Map<String, String> returned,
  ) {
    // The return value wins over the initiate value: Khalti appends the pidx
    // it actually processed, which is the one the lookup must ask about.
    final pidx = returned['pidx'] ?? PaymentGateway._str(order, 'pidx') ?? '';
    return _lookup(pidx);
  }

  @override
  Future<GatewayVerdict> Function()? poll(PlacedOrder order) {
    final pidx = PaymentGateway._str(order, 'pidx');
    return pidx == null ? null : () => _lookup(pidx);
  }

  Future<GatewayVerdict> _lookup(String pidx) async {
    final body = await CheckoutRepository.instance.confirmPayment(
      '/payments/khalti/lookup',
      {'pidx': pidx},
    );
    final status = asString(body['status']);
    return GatewayVerdict(
      paid: body['success'] == true && status == 'success',
      status: status,
      message: asString(body['message']) ?? asString(body['error']),
    );
  }
}

/// eSewa: a signed form, correlated by a base64 envelope on the way back.
class EsewaGateway extends PaymentGateway {
  const EsewaGateway();

  @override
  String get id => 'esewa';

  /// Where the signed form goes when the server names no endpoint of its own.
  ///
  /// eSewa's published v2 form URL, and the same constant the storefront falls
  /// back to. A server-supplied `actionUrl` always wins, so a shop pointed at
  /// eSewa's test host keeps working.
  static const _formUrl = 'https://epay.esewa.com.np/api/epay/main/v2/form';

  @override
  GatewayLaunch launch(PlacedOrder order) {
    // `esewaConfig` is what the server actually sends -- the same
    // `<gateway>Config` shape as connectIPS -- and reading only the other two
    // names is why this never launched. The rest are older spellings, kept
    // because a server that answers with one of them still works.
    final fields = [
      asMap(order.gateway['esewaConfig']),
      asMap(order.gateway['formFields']),
      asMap(order.gateway['fields']),
    ].firstWhere((bag) => bag.isNotEmpty, orElse: () => const {});
    // The signed fields are the part only the server can produce; the endpoint
    // they post to is a constant eSewa publishes, and our server does not
    // always send it. Failing for want of a well-known URL would strand a
    // perfectly good signature.
    final action = PaymentGateway._str(order, 'actionUrl') ?? _formUrl;
    if (fields.isEmpty) PaymentGateway._missing('a form');
    return GatewayLaunch.form(action, fields);
  }

  @override
  Future<GatewayVerdict> confirm(
    PlacedOrder order,
    Map<String, String> returned,
  ) async {
    final data = returned['data'];
    if (data == null) {
      // Not a protocol error, which is how this used to read. eSewa carries
      // the envelope on its success URL only; a shopper who cancels, or a
      // payment that does not go through, comes back through the failure URL
      // with nothing attached. Measured against production. Treating it as
      // abandoned is what nothing-was-charged actually means, and it leaves
      // the retry offered -- throwing here reported a working cancellation as
      // "eSewa did not send the confirmation back" and refused a second try.
      return const GatewayVerdict(paid: false, abandoned: true);
    }

    final body = await CheckoutRepository.instance.confirmPayment(
      '/payments/esewa/verify',
      {'data': data},
    );
    // Success alone, deliberately. eSewa's verify does not carry a status and
    // requiring one would reject every good payment.
    return GatewayVerdict(
      paid: body['success'] == true,
      status: asString(body['status']),
      message: asString(body['message']) ?? asString(body['error']),
    );
  }

  // No server-to-server probe: the envelope only exists in the return URL, so
  // a shopper who never came back can only be resolved by polling the order.
}

/// connectIPS: a signed form, correlated by `txnId`.
class ConnectIpsGateway extends PaymentGateway {
  const ConnectIpsGateway();

  @override
  String get id => 'connectips';

  @override
  GatewayLaunch launch(PlacedOrder order) {
    final action = PaymentGateway._str(order, 'actionUrl');
    final fields = asMap(order.gateway['connectipsConfig']);
    if (action == null || fields.isEmpty) PaymentGateway._missing('a form');
    return GatewayLaunch.form(action, fields);
  }

  @override
  Future<GatewayVerdict> confirm(
    PlacedOrder order,
    Map<String, String> returned,
  ) {
    // The initiate value wins here, the opposite of Khalti: connectIPS returns
    // to a static URL and appends only TXNID, which can be absent entirely.
    final txnId =
        PaymentGateway._str(order, 'txnId') ??
        returned['TXNID'] ??
        returned['txnId'] ??
        '';
    return _check(txnId);
  }

  @override
  Future<GatewayVerdict> Function()? poll(PlacedOrder order) {
    final txnId = PaymentGateway._str(order, 'txnId');
    return txnId == null ? null : () => _check(txnId);
  }

  Future<GatewayVerdict> _check(String txnId) async {
    final body = await CheckoutRepository.instance.confirmPayment(
      '/payments/connectips/check-status',
      {'txnId': txnId},
    );
    final status = asString(body['status']);
    return GatewayVerdict(
      paid: body['success'] == true && status == 'success',
      status: status,
      message: asString(body['message']) ?? asString(body['error']),
    );
  }
}

/// NPS: a signed form nested under `gatewayConfig`.
class NpsGateway extends PaymentGateway {
  const NpsGateway();

  @override
  String get id => 'nps';

  @override
  GatewayLaunch launch(PlacedOrder order) {
    final config = asMap(order.gateway['gatewayConfig']);
    final action = asString(config['actionUrl']);
    final fields = asMap(config['fields']);
    if (action == null || fields.isEmpty) PaymentGateway._missing('a form');
    return GatewayLaunch.form(action, fields);
  }

  /// The merchant transaction id, which NPS buries inside the signed field bag.
  static String _merchantTxn(PlacedOrder order) =>
      asString(
        asMap(asMap(order.gateway['gatewayConfig'])['fields'])['MerchantTxnId'],
      ) ??
      '';

  @override
  Future<GatewayVerdict> confirm(
    PlacedOrder order,
    Map<String, String> returned,
  ) {
    final fromInitiate = _merchantTxn(order);
    return _check(
      fromInitiate.isNotEmpty
          ? fromInitiate
          : (returned['MerchantTxnId'] ?? ''),
      returned['GatewayTxnId'],
    );
  }

  @override
  Future<GatewayVerdict> Function()? poll(PlacedOrder order) {
    final txn = _merchantTxn(order);
    return txn.isEmpty ? null : () => _check(txn, null);
  }

  Future<GatewayVerdict> _check(
    String merchantTxnId,
    String? gatewayTxnId,
  ) async {
    final body = await CheckoutRepository.instance.confirmPayment(
      '/payments/nps/check-status',
      {
        'merchantTxnId': merchantTxnId,
        // Omitted, not null: the server treats an absent key and a null
        // differently when deciding which record to look up.
        'gatewayTxnId': ?gatewayTxnId,
      },
    );
    final status = asString(body['status']);
    return GatewayVerdict(
      paid: body['success'] == true && status == 'success',
      status: status,
      message: asString(body['message']) ?? asString(body['error']),
      // NPS alone can say whether the shopper actually started paying. Without
      // it, someone who opened the page and closed it reads as a failure.
      abandoned: body['started'] == false,
    );
  }
}

/// Fonepay: a hosted page whose return is signed across the whole query string.
class FonepayGateway extends PaymentGateway {
  const FonepayGateway();

  @override
  String get id => 'fonepay';

  @override
  GatewayLaunch launch(PlacedOrder order) {
    final url = PaymentGateway._str(order, 'paymentUrl');
    if (url == null) PaymentGateway._missing('a payment page');
    return GatewayLaunch.redirect(url);
  }

  @override
  Future<GatewayVerdict> confirm(
    PlacedOrder order,
    Map<String, String> returned,
  ) async {
    // Passed through untouched. A DV signature covers every parameter, so
    // dropping, renaming or reordering one invalidates it. The single
    // permitted change is adding the uppercase alias the verifier expects.
    final payload = <String, dynamic>{...returned};
    if (!payload.containsKey('PRN') && returned.containsKey('prn')) {
      payload['PRN'] = returned['prn'];
    }

    final body = await CheckoutRepository.instance.confirmPayment(
      '/payments/fonepay/verify',
      payload,
    );
    final status = asString(body['status']);
    return GatewayVerdict(
      // A negative test, uniquely. Fonepay reports a good payment with a status
      // this app has no list of, so anything that is not an explicit failure
      // counts.
      paid: body['success'] == true && status != 'failed',
      status: status,
      message: asString(body['message']) ?? asString(body['error']),
    );
  }

  // No server-to-server probe: verify needs the signed return parameters.
}
