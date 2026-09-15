import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// One movement in and out of the wallet.
class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.amount,
    this.note = '',
    this.at,
    this.status = '',
    this.orderNumber = '',
  });

  final String id;

  /// Positive is earned, negative is spent. The server is inconsistent about
  /// which field carries it, so both are read.
  final num amount;

  final String note;
  final DateTime? at;

  /// What the server calls the state of this movement, or empty when it does
  /// not say.
  ///
  /// Read under several names and rendered only when present. The alternative
  /// -- defaulting it to "Completed" -- would put a word on screen that the
  /// server never said, about money.
  final String status;

  /// The order this movement belongs to, when it belongs to one.
  ///
  /// Same rule: shown only if the server names it. Coins move for reasons that
  /// have no order behind them, and captioning those with a blank reference
  /// would invent a relationship.
  final String orderNumber;

  bool get isCredit => amount >= 0;

  factory WalletEntry.fromJson(Map<String, dynamic> json) => WalletEntry(
    id: asString(json['id']) ?? '',
    amount: asNum(json['amount']) ?? asNum(json['value']) ?? 0,
    note:
        asString(json['description']) ??
        asString(json['note']) ??
        asString(json['type']) ??
        '',
    at: asDate(json['created_at']) ?? asDate(json['createdAt']),
    status: asString(json['status']) ?? asString(json['state']) ?? '',
    orderNumber:
        asString(json['order_number']) ??
        asString(json['orderNumber']) ??
        asString(json['order_id']) ??
        asString(json['orderId']) ??
        '',
  );
}

/// The shopper's coin balance and what moved it.
///
/// `GET /wallet` answers **401** rather than 404 without a session, which is
/// what says the wallet is real and belongs to an account -- the coins card on
/// the home page leads here rather than to an invented page.
///
/// The balance is read under several names because the response shape is not
/// published anywhere this app can see, and a wallet that renders zero because
/// the field was called something else would be worse than one that fails.
class WalletRepository {
  WalletRepository._();

  static final WalletRepository instance = WalletRepository._();

  Dio get _dio => ApiClient.http;

  Future<num> balance() => guarded(() async {
    final res = await _dio.get('/wallet');
    final body = asMap(res.data);
    final wallet = asMap(body['wallet']);
    return asNum(body['balance']) ??
        asNum(body['coins']) ??
        asNum(body['available_balance']) ??
        asNum(wallet['balance']) ??
        asNum(wallet['coins']) ??
        0;
  });

  Future<List<WalletEntry>> transactions() => guarded(() async {
    final res = await _dio.get('/wallet/transactions');
    return asRows(res.data, key: 'transactions')
        .map(WalletEntry.fromJson)
        .where((entry) => entry.id.isNotEmpty)
        .toList(growable: false);
  });
}
