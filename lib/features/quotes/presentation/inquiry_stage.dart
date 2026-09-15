import '../data/quote_repository.dart';

/// The four steps an inquiry goes through, as the reference draws them.
///
/// The server keeps five statuses; these are the stages a shopper is shown.
/// Nothing here is stored: the stage is read off the status the server sent,
/// so a queue that moves a request forward moves this timeline with it.
enum InquiryStage {
  submitted('Inquiry Submitted', 'Your inquiry has been received by our team.'),
  sourcing(
    'Sourcing & Supplier Matching',
    'We are reaching out to verified suppliers.',
  ),
  quotation('Quotation', 'You will be notified once we receive a quote.'),
  closed('Closed', 'Inquiry will be marked as closed after your confirmation.');

  const InquiryStage(this.title, this.detail);

  final String title;
  final String detail;

  /// How far [status] has got.
  ///
  /// A status this app has not heard of counts as submitted and no further:
  /// the request exists, and guessing it had been quoted would tell somebody
  /// a price is coming that nobody has promised.
  static InquiryStage of(QuoteStatus status) => switch (status) {
    QuoteStatus.pending => InquiryStage.submitted,
    QuoteStatus.reviewing => InquiryStage.sourcing,
    QuoteStatus.quoted || QuoteStatus.approved => InquiryStage.quotation,
    QuoteStatus.rejected => InquiryStage.closed,
    QuoteStatus.other => InquiryStage.submitted,
  };

  /// Whether this step is behind [current].
  bool isBefore(InquiryStage current) => index < current.index;
}
