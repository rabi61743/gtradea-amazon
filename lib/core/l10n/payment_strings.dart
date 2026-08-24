/// Everything the payment flow says, in one place per language.
///
/// Named fields rather than a map, so adding a string without translating it is
/// a compile error rather than an English word appearing in a Nepali checkout.
class PaymentStrings {
  const PaymentStrings({
    required this.title,
    required this.chooseMethod,
    required this.noMethods,
    required this.savedCards,
    required this.useNewCard,
    required this.saveThisCard,
    required this.saveCardNote,
    required this.removeCard,
    required this.removeCardConfirm,
    required this.expired,
    required this.cardNumber,
    required this.cardHolder,
    required this.expiry,
    required this.cvv,
    required this.cvvHelp,
    required this.orderTotal,
    required this.discount,
    required this.deliveryFee,
    required this.vatIncluded,
    required this.finalAmount,
    required this.payableNow,
    required this.payableOnDelivery,
    required this.payNow,
    required this.placeOrder,
    required this.creatingOrder,
    required this.contactingGateway,
    required this.paymentSuccessful,
    required this.paidWith,
    required this.orderPlaced,
    required this.payOnDelivery,
    required this.paymentFailed,
    required this.paymentCancelled,
    required this.cancelledDetail,
    required this.orderStillExists,
    required this.tryAgain,
    required this.chooseAnother,
    required this.trackOrder,
    required this.done,
    required this.securityNote,
  });

  final String title;
  final String chooseMethod;
  final String noMethods;

  final String savedCards;
  final String useNewCard;
  final String saveThisCard;
  final String saveCardNote;
  final String removeCard;
  final String removeCardConfirm;
  final String expired;

  final String cardNumber;
  final String cardHolder;
  final String expiry;
  final String cvv;
  final String cvvHelp;

  final String orderTotal;
  final String discount;
  final String deliveryFee;
  final String vatIncluded;
  final String finalAmount;
  final String payableNow;
  final String payableOnDelivery;

  final String payNow;
  final String placeOrder;
  final String creatingOrder;
  final String contactingGateway;

  final String paymentSuccessful;

  /// Takes the method's name: "Paid with Khalti".
  final String Function(String method) paidWith;

  final String orderPlaced;
  final String payOnDelivery;
  final String paymentFailed;
  final String paymentCancelled;
  final String cancelledDetail;

  /// Takes the order number. The single most important sentence on a failure
  /// screen when the order was created before the payment broke.
  final String Function(String orderNumber) orderStillExists;

  final String tryAgain;
  final String chooseAnother;
  final String trackOrder;
  final String done;
  final String securityNote;

  static final en = PaymentStrings(
    title: 'Payment',
    chooseMethod: 'How would you like to pay?',
    noMethods: 'No payment method is available just now. Please try later.',
    savedCards: 'Saved cards',
    useNewCard: 'Use a different card',
    saveThisCard: 'Remember this card',
    saveCardNote: 'Only the brand, last four digits and expiry are kept. The '
        'card number and security code are never stored.',
    removeCard: 'Remove',
    removeCardConfirm: 'Remove this card?',
    expired: 'Expired',
    cardNumber: 'Card number',
    cardHolder: 'Name on card',
    expiry: 'Expiry (MM/YY)',
    cvv: 'Security code',
    cvvHelp: 'The code on the back of your card. It is used once and never '
        'saved.',
    orderTotal: 'Order total',
    discount: 'Discount',
    deliveryFee: 'Delivery',
    vatIncluded: 'VAT included',
    finalAmount: 'Amount due',
    payableNow: 'Pay now',
    payableOnDelivery: 'Pay on delivery',
    payNow: 'Pay',
    placeOrder: 'Place order',
    creatingOrder: 'Creating your order',
    contactingGateway: 'Taking you to your payment provider',
    paymentSuccessful: 'Payment successful',
    paidWith: (method) => 'Paid with $method',
    orderPlaced: 'Order placed',
    payOnDelivery: 'Pay the courier when it arrives',
    paymentFailed: 'Payment failed',
    paymentCancelled: 'Payment cancelled',
    cancelledDetail: 'Nothing has been charged. You can pay another way or try '
        'again.',
    orderStillExists: (number) =>
        'Your order $number was created and is waiting for payment. You can pay '
        'for it from your orders.',
    tryAgain: 'Try again',
    chooseAnother: 'Choose another method',
    trackOrder: 'Track order',
    done: 'Done',
    securityNote: 'Your card details go straight to the payment provider. This '
        'app never stores your card number or security code.',
  );

  /// A first pass, and worth a native speaker's eye before it ships. Where the
  /// borrowed term is what Nepali shoppers actually say -- कार्ड, भ्याट --
  /// the loanword is kept rather than a coinage nobody uses.
  static final ne = PaymentStrings(
    title: 'भुक्तानी',
    chooseMethod: 'कसरी भुक्तानी गर्न चाहनुहुन्छ?',
    noMethods: 'अहिले कुनै भुक्तानी विधि उपलब्ध छैन। पछि प्रयास गर्नुहोस्।',
    savedCards: 'सुरक्षित कार्डहरू',
    useNewCard: 'अर्को कार्ड प्रयोग गर्नुहोस्',
    saveThisCard: 'यो कार्ड सम्झ्नुहोस्',
    saveCardNote: 'कार्डको प्रकार, अन्तिम चार अंक र म्याद मात्र राखिन्छ। '
        'कार्ड नम्बर र सुरक्षा कोड कहिल्यै सुरक्षित गरिँदैन।',
    removeCard: 'हटाउनुहोस्',
    removeCardConfirm: 'यो कार्ड हटाउने?',
    expired: 'म्याद सकिएको',
    cardNumber: 'कार्ड नम्बर',
    cardHolder: 'कार्डमा लेखिएको नाम',
    expiry: 'म्याद (MM/YY)',
    cvv: 'सुरक्षा कोड',
    cvvHelp: 'कार्डको पछाडि लेखिएको कोड। एक पटक मात्र प्रयोग हुन्छ, सुरक्षित '
        'गरिँदैन।',
    orderTotal: 'अर्डर जम्मा',
    discount: 'छुट',
    deliveryFee: 'डेलिभरी',
    vatIncluded: 'भ्याट समावेश',
    finalAmount: 'तिर्नुपर्ने रकम',
    payableNow: 'अहिले तिर्नुहोस्',
    payableOnDelivery: 'डेलिभरीमा तिर्नुहोस्',
    payNow: 'भुक्तानी',
    placeOrder: 'अर्डर गर्नुहोस्',
    creatingOrder: 'तपाईंको अर्डर बनाइँदै छ',
    contactingGateway: 'भुक्तानी सेवामा लगिँदै छ',
    paymentSuccessful: 'भुक्तानी सफल',
    paidWith: (method) => '$method बाट भुक्तानी भयो',
    orderPlaced: 'अर्डर भयो',
    payOnDelivery: 'सामान आउँदा कुरियरलाई तिर्नुहोस्',
    paymentFailed: 'भुक्तानी असफल',
    paymentCancelled: 'भुक्तानी रद्द भयो',
    cancelledDetail: 'कुनै रकम काटिएको छैन। अर्को तरिकाले वा फेरि प्रयास '
        'गर्न सक्नुहुन्छ।',
    orderStillExists: (number) =>
        'तपाईंको अर्डर $number बनेको छ र भुक्तानी कुरिरहेको छ। अर्डरहरूबाट '
        'भुक्तानी गर्न सक्नुहुन्छ।',
    tryAgain: 'फेरि प्रयास गर्नुहोस्',
    chooseAnother: 'अर्को विधि छान्नुहोस्',
    trackOrder: 'अर्डर ट्रयाक गर्नुहोस्',
    done: 'भयो',
    securityNote: 'तपाईंको कार्ड विवरण सिधै भुक्तानी सेवामा जान्छ। यो एपले '
        'कार्ड नम्बर वा सुरक्षा कोड कहिल्यै राख्दैन।',
  );
}
