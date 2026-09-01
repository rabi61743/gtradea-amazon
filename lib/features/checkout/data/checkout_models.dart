import '../../../core/network/json.dart';
import '../../address/data/address_store.dart';

/// Where an order is going, in the shape the gateway wants it.
///
/// The Nepal assumptions are deliberate and load-bearing: the district goes
/// into both `city` and `state` because the freight calculation keys on one
/// and the stored address displays the other, and sending only one breaks
/// whichever half is missing.
class CheckoutAddress {
  const CheckoutAddress({
    required this.firstName,
    required this.lastName,
    required this.address,
    required this.city,
    this.address2,
    this.state,
    this.zipCode,
    this.country = 'Nepal',
    this.phone,
  });

  final String firstName;
  final String lastName;
  final String address;
  final String? address2;
  final String city;
  final String? state;
  final String? zipCode;
  final String country;

  /// International form. The local number alone is not dialable by a courier
  /// system that assumes E.164.
  final String? phone;

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'address': address,
    // Omitted rather than sent empty throughout: the server treats an
    // absent key and an empty string differently.
    'address2': ?_orNull(address2),
    'city': city,
    'state': ?_orNull(state),
    'zipCode': ?_orNull(zipCode),
    'country': country,
    'phone': ?_orNull(phone),
  };

  static String? _orNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  /// Built from a saved address.
  ///
  /// [fallbackPhone] is the account's own number, used when the address has
  /// none. **The server rejects an order with no phone** -- `Phone is required`,
  /// measured against production -- and the new-address form no longer asks for
  /// one, so without this fallback an address saved today can never be ordered
  /// to. A courier needs a number to ring; whose address it is and whose account
  /// it is are the same person, so the account's number is the right one.
  factory CheckoutAddress.fromAddress(
    Address address, {
    String? fallbackPhone,
  }) {
    final names = address.fullName.trim().split(RegExp(r'\s+'));
    final raw = address.phone.trim().isEmpty
        ? (fallbackPhone ?? '')
        : address.phone;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    return CheckoutAddress(
      firstName: names.isEmpty ? '' : names.first,
      lastName: names.length > 1 ? names.sublist(1).join(' ') : '',
      address: [
        address.area,
        address.landmark,
      ].whereType<String>().where((part) => part.isNotEmpty).join(', '),
      // The district in both, on purpose. See the class doc.
      city: address.city,
      state: address.province,
      zipCode: address.postalCode,
      phone: digits.isEmpty
          ? null
          : '+977${digits.startsWith('977') ? digits.substring(3) : digits}',
    );
  }
}

/// Everything the server needs to turn a cart into an order.
///
/// Write-only. Three of these keys are conditional and a port that always
/// emits them changes what the server builds: an empty `selectedCartItemIds`
/// is not the same as an absent one (absent means "price the whole cart"),
/// `walletApply: 0` must be absent, and `paymentMethod` is absent for most
/// gateways.
class CheckoutOrderInput {
  const CheckoutOrderInput({
    required this.shippingAddress,
    this.billingType = 'individual',
    this.companyName,
    this.taxId,
    this.selectedCartItemIds = const [],
    this.promoCode,
    this.shippingMode = 'land',
    this.combine = false,
    this.termsAccepted = false,
    this.walletApply = 0,
  });

  final CheckoutAddress shippingAddress;

  /// 'individual' or 'business'. A business order carries a company name and a
  /// tax id; a personal one carries neither.
  final String billingType;
  final String? companyName;
  final String? taxId;

  /// Which cart rows this order is for. Empty means all of them.
  final List<String> selectedCartItemIds;

  final String? promoCode;
  final String shippingMode;
  final bool combine;
  final bool termsAccepted;
  final num walletApply;

  Map<String, dynamic> toJson({String? paymentMethod}) {
    final shipping = shippingAddress.toJson();
    final isBusiness = billingType == 'business';

    return {
      'shippingAddress': shipping,
      // The app offers no separate billing address, so this is the shipping one
      // with the tax fields added.
      'billingAddress': {
        ...shipping,
        'billingType': billingType,
        if (isBusiness && (companyName?.isNotEmpty ?? false))
          'companyName': companyName,
        if (isBusiness && (taxId?.isNotEmpty ?? false)) 'taxId': taxId,
      },
      'paymentMethod': ?paymentMethod,
      if (selectedCartItemIds.isNotEmpty)
        'selectedCartItemIds': selectedCartItemIds,
      'promoCode': ?(promoCode?.isEmpty ?? true ? null : promoCode),
      'shippingMode': shippingMode,
      // Constants, and they must stay constants: freight is quoted on actual
      // weight and collected at the door, so it never enters the amount a
      // gateway charges. Wiring the delivery quote in here would charge for it
      // twice.
      'freightCost': 0,
      'freightBasis': 'none',
      'combine': combine,
      'termsAccepted': termsAccepted,
      if (walletApply > 0) 'walletApply': walletApply,
    };
  }
}

/// What the server made of the order.
class PlacedOrder {
  const PlacedOrder({
    required this.orderId,
    required this.orderNumber,
    this.advanceAmount,
    this.remainingAmount,
    this.paidByWallet = false,
    this.gateway = const {},
  });

  final String orderId;
  final String orderNumber;

  /// What the gateway is being asked for now, and what is due later. The
  /// server's figures, which are the ones that get charged -- the app shows
  /// its own estimate before this point and must defer to these after.
  final num? advanceAmount;
  final num? remainingAmount;

  /// True when store credit covered the whole advance. The order is already
  /// paid and there is no gateway payload at all, whichever method was asked
  /// for -- so this has to be checked before reaching for one.
  final bool paidByWallet;

  /// The gateway's own launch payload. Every provider shapes this differently,
  /// so it is carried through untouched.
  final Map<String, dynamic> gateway;

  factory PlacedOrder.fromJson(Map<String, dynamic> json) => PlacedOrder(
    // Not `.toString()`: a missing value would become the literal string
    // "null" and then be used to build a request path.
    orderId: asString(json['orderId']) ?? asString(json['order_id']) ?? '',
    orderNumber:
        asString(json['orderNumber']) ?? asString(json['order_number']) ?? '',
    advanceAmount: asNum(json['advanceAmount']),
    remainingAmount: asNum(json['remainingAmount']),
    paidByWallet: asBool(json['paidByWallet']),
    gateway: json,
  );
}
