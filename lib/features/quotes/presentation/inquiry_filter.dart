import '../data/quote_repository.dart';

/// The tabs the inquiry list is filtered by.
///
/// Four buckets over the server's five statuses, which is what the reference
/// design shows. The server is not asked to group anything: the list arrives
/// whole from `/product-requests` and is sorted here, so switching tabs costs
/// no request and cannot show a shopper a stale count.
enum InquiryFilter {
  all('All'),
  underReview('Under Review'),
  quoted('Quoted'),
  closed('Closed');

  const InquiryFilter(this.label);

  final String label;

  /// Whether [status] belongs in this bucket.
  ///
  /// A status this app does not know sits in All alone. Guessing which bucket
  /// a sixth server state belongs to would file it under a word the server
  /// never used.
  bool covers(QuoteStatus status) => switch (this) {
    InquiryFilter.all => true,
    InquiryFilter.underReview =>
      status == QuoteStatus.pending || status == QuoteStatus.reviewing,
    InquiryFilter.quoted =>
      status == QuoteStatus.quoted || status == QuoteStatus.approved,
    InquiryFilter.closed => status == QuoteStatus.rejected,
  };

  /// How many of [requests] this tab holds.
  int count(Iterable<QuoteRequest> requests) =>
      requests.where((r) => covers(r.status)).length;
}
