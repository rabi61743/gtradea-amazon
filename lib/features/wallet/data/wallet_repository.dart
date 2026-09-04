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
  });

  final String id;

  /// Positive is earned, negative is spent. The server is inconsistent about
  /// which field carries it, so both are read.
  final num amount;

  final String note;
  final DateTime? at;

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
