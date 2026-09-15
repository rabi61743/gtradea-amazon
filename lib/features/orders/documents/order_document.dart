import '../../../core/network/json.dart';
import '../data/orders_repository.dart';

/// Which paper an order gets.
///
/// Decided by the status the server holds for the order, and nothing else.
enum OrderDocumentKind {
  invoice('Invoice'),
  receipt('Receipt');

  const OrderDocumentKind(this.label);

  /// "Invoice" or "Receipt" -- on the button, in the file name, on the page.
  final String label;

  /// Completed or delivered is an invoice. Anything short of that -- pending,
  /// processing, shipped, out for delivery, cancelled, a state the server adds
  /// tomorrow -- is a receipt.
  ///
  /// The whole status is compared rather than a substring of it.
  /// [ServerOrder.isDelivered] matches "deliver" anywhere, which is right for
  /// what it guards, but it would call `out_for_delivery` and
  /// `delivery_failed` delivered -- and an invoice for a parcel that is still
  /// on the road is a document the shop cannot stand behind.
  static OrderDocumentKind forStatus(String status) {
    final normalised = status
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), ' ');
    return _complete.contains(normalised) ? invoice : receipt;
  }

  static const _complete = {'delivered', 'completed', 'complete', 'fulfilled'};
}

/// Raised when an order has nothing a document could honestly be made of.
class OrderDocumentUnavailable implements Exception {
  const OrderDocumentUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One line of the document, as the server recorded it.
class OrderDocumentLine {
  const OrderDocumentLine({
    required this.name,
    required this.quantity,
    this.variant,
    this.unitPrice,
  });

  final String name;
  final String? variant;
  final int quantity;

  /// Null when the server did not record one. Printed as a dash, not a zero:
  /// a zero is a claim that the item was free.
  final num? unitPrice;

  num? get amount => unitPrice == null ? null : unitPrice! * quantity;
}

/// An invoice or a receipt, built from one order the server returned.
///
/// Every figure here is the server's. Optional charges -- delivery, discount,
/// tax -- and billing details appear only when the server sent them; nothing
/// is filled in with a guess or a zero. The one derived figure is the VAT note
/// when the server gives no tax of its own, and it uses the same rule and the
/// same words as the order summary in the app.
class OrderDocument {
  const OrderDocument({
    required this.kind,
    required this.number,
    required this.fileName,
    required this.orderNumber,
    required this.orderId,
    required this.status,
    required this.lines,
    required this.subtotal,
    required this.total,
    required this.issuedAt,
    this.placedAt,
    this.completedAt,
    this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.addressLines = const [],
    this.companyName,
    this.taxId,
    this.discount,
    this.couponCode,
    this.delivery,
    this.adjustment,
    this.tax,
    this.taxFromServer = false,
    this.advancePaid,
    this.balanceDue,
    this.paymentMethod,
    this.paymentStatus,
  });

  final OrderDocumentKind kind;

  /// The document's own number: the server's invoice or receipt number when
  /// it has one, and otherwise the order number printed on the order.
  final String number;

  /// `Invoice-{number}.pdf`, `Receipt-{number}.pdf`, or the file name the
  /// server gave the document.
  final String fileName;

  final String orderNumber;
  final String orderId;

  /// The server's own word for where the order is, made readable.
  final String status;

  final DateTime? placedAt;

  /// When the order was delivered or completed, where the server said.
  final DateTime? completedAt;

  /// When this copy of the document was produced.
  final DateTime issuedAt;

  final String? customerName;
  final String? customerEmail;
  final String? customerPhone;
  final List<String> addressLines;

  /// Present on a business order: checkout sends both with the billing
  /// address.
  final String? companyName;
  final String? taxId;

  final List<OrderDocumentLine> lines;

  final num subtotal;
  final num? discount;
  final String? couponCode;
  final num? delivery;

  /// The difference between the server's total and the lines, when the server
  /// gave the total but not what made it up. Printed under its own label
  /// rather than being passed off as delivery or as a discount.
  final num? adjustment;

  /// The server's tax figure, or -- when it sent none -- the VAT already inside
  /// the prices, back-solved the way the app's own order summary does it.
  final num? tax;
  final bool taxFromServer;

  final num total;
  final num? advancePaid;
  final num? balanceDue;

  final String? paymentMethod;
  final String? paymentStatus;

  /// Builds the document from the order the server returned.
  ///
  /// [accountEmail] is the signed-in shopper's address, used only when the
  /// order itself carries none.
  factory OrderDocument.fromOrder(
    ServerOrder order, {
    String? accountEmail,
    DateTime? issuedAt,
  }) {
    final raw = order.raw;
    final kind = OrderDocumentKind.forStatus(order.status);

    final reference = order.orderNumber.isNotEmpty ? order.orderNumber : order.id;
    final number =
        _firstString(
          raw,
          kind == OrderDocumentKind.invoice
              ? const ['invoice_number', 'invoice_no']
              : const ['receipt_number', 'receipt_no'],
        ) ??
        reference;

    final lines = [
      for (final item in order.items)
        OrderDocumentLine(
          name: item.name,
          variant: (item.variantLabel?.trim().isEmpty ?? true)
              ? null
              : item.variantLabel!.trim(),
          quantity: item.quantity,
          unitPrice: item.unitPrice,
        ),
    ];

    final itemsTotal = lines.fold<num>(0, (sum, line) => sum + (line.amount ?? 0));
    final subtotal = _firstNum(raw, const ['subtotal', 'sub_total']) ?? itemsTotal;

    final discount = _nonZero(
      _firstNum(raw, const [
        'discount_amount',
        'coupon_discount',
        'promo_discount',
        'discount',
      ]),
    );
    final delivery = _firstNum(raw, const [
      'shipping_amount',
      'shipping_cost',
      'shipping_fee',
      'shipping_charge',
      'delivery_fee',
      'delivery_charge',
      'freight_amount',
    ]);
    final serverTax = _nonZero(
      _firstNum(raw, const ['tax_amount', 'vat_amount', 'tax']),
    );

    final total =
        order.totalAmount ?? (subtotal - (discount ?? 0) + (delivery ?? 0));

    // What the total holds beyond the lines, when the server did not break it
    // down. Anything under half a rupee is rounding, not a charge.
    num? adjustment;
    if (delivery == null && discount == null) {
      final gap = total - subtotal;
      if (gap.abs() >= 0.5) adjustment = gap;
    }

    final address = order.shippingAddress;
    final billing = asMap(raw['billing_address'] ?? raw['billingAddress']);

    final advance = _nonZero(order.advanceAmount);
    final remaining = order.remainingAmount;

    return OrderDocument(
      kind: kind,
      number: number,
      fileName: _fileName(kind, raw, number),
      orderNumber: reference,
      orderId: order.id,
      status: _readable(order.status) ?? 'Unknown',
      placedAt: order.placedAt,
      completedAt: kind == OrderDocumentKind.invoice
          ? (asDate(raw['delivered_at']) ?? asDate(raw['completed_at']))
          : null,
      issuedAt: issuedAt ?? DateTime.now(),
      customerName:
          _firstString(address, const ['full_name', 'name']) ??
          _firstString(billing, const ['full_name', 'name', 'fullName']),
      customerEmail:
          _firstString(address, const ['email']) ??
          _firstString(raw, const ['customer_email', 'email', 'user_email']) ??
          _clean(accountEmail),
      customerPhone: _firstString(address, const ['phone', 'phone_number']),
      addressLines: _addressLines(address),
      companyName: _firstString(billing, const ['companyName', 'company_name']),
      taxId: _firstString(billing, const [
        'taxId',
        'tax_id',
        'vat_number',
        'pan_number',
      ]),
      lines: lines,
      subtotal: subtotal,
      discount: discount,
      couponCode: discount == null
          ? null
          : _firstString(raw, const ['coupon_code', 'promo_code']),
      delivery: delivery,
      adjustment: adjustment,
      tax: serverTax ?? (subtotal - (discount ?? 0)) * 13 / 113,
      taxFromServer: serverTax != null,
      total: total,
      advancePaid: advance,
      balanceDue: advance == null ? null : remaining,
      paymentMethod: _paymentMethod(order.paymentMethod),
      paymentStatus: _readable(order.paymentStatus),
    );
  }

  /// The server's file name for the document if it gave one, and otherwise
  /// `Invoice-{number}.pdf` or `Receipt-{number}.pdf`.
  static String _fileName(
    OrderDocumentKind kind,
    Map<String, dynamic> raw,
    String number,
  ) {
    final given = _firstString(
      raw,
      kind == OrderDocumentKind.invoice
          ? const ['invoice_file_name', 'invoice_filename']
          : const ['receipt_file_name', 'receipt_filename'],
    );
    if (given != null) {
      final safe = _safeFileSegment(given);
      if (safe.isNotEmpty) {
        return safe.toLowerCase().endsWith('.pdf') ? safe : '$safe.pdf';
      }
    }
    return '${kind.label}-${_safeFileSegment(number)}.pdf';
  }

  /// Keeps a file name to what every file system and share target accepts.
  static String _safeFileSegment(String value) => value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static List<String> _addressLines(Map<String, dynamic> address) {
    final street = [
      _firstString(address, const ['address_line1', 'street']),
      _firstString(address, const ['address_line2']),
    ].whereType<String>().join(', ');
    final area = [
      _firstString(address, const ['city']),
      _firstString(address, const ['state']),
      _firstString(address, const ['postal_code']),
    ].whereType<String>().join(', ');
    return [
      if (street.isNotEmpty) street,
      if (area.isNotEmpty) area,
      ?_firstString(address, const ['country']),
    ];
  }

  static String? _paymentMethod(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    if (value.isEmpty) return null;
    // The one code the app already names: it is how the payment card reads it.
    if (value == 'cod' || value.contains('cash')) return 'Cash on delivery';
    return _readable(raw);
  }

  /// `out_for_delivery` as "Out for delivery": the server's word, readable.
  static String? _readable(String? raw) {
    final value = raw?.replaceAll(RegExp(r'[_-]+'), ' ').trim() ?? '';
    if (value.isEmpty) return null;
    return value[0].toUpperCase() + value.substring(1);
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static num? _nonZero(num? value) => (value == null || value == 0) ? null : value;

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = _clean(asString(map[key]));
      if (value != null) return value;
    }
    return null;
  }

  static num? _firstNum(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = asNum(map[key]);
      if (value != null) return value;
    }
    return null;
  }
}
