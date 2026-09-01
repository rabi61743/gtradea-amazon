import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/config/env.dart';

/// The gateway's own page, hosted in the app.
///
/// The shopper's card or wallet credentials are entered on the provider's
/// page, never on ours. This screen watches for the redirect back and reads the
/// parameters off it; it never sees what was typed.
///
/// Two ways in, because the providers differ and cannot be unified:
///
///   * a URL to open (Khalti, Fonepay)
///   * a form to POST (eSewa, connectIPS, NPS), whose fields are signed
///     server-side and must be sent exactly as received
class PaymentWebViewScreen extends StatefulWidget {
  const PaymentWebViewScreen({
    super.key,
    required this.title,
    this.redirectUrl,
    this.actionUrl,
    this.formFields,
  }) : assert(
         redirectUrl != null || (actionUrl != null && formFields != null),
         'a gateway needs either a URL to open or a form to post',
       );

  final String title;

  /// For providers that hand back a hosted page to visit.
  final String? redirectUrl;

  /// For providers that expect a signed form POST.
  final String? actionUrl;
  final Map<String, dynamic>? formFields;

  /// Returns the return URL's query parameters, or null if the shopper backed
  /// out before the gateway sent them back.
  static Future<Map<String, String>?> show(
    BuildContext context, {
    required String title,
    String? redirectUrl,
    String? actionUrl,
    Map<String, dynamic>? formFields,
  }) {
    return Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaymentWebViewScreen(
          title: title,
          redirectUrl: redirectUrl,
          actionUrl: actionUrl,
          formFields: formFields,
        ),
      ),
    );
  }

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  /// Guards the pop. A gateway can fire several navigations at the return URL
  /// and popping twice would take the checkout screen with it.
  bool _returned = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => _setLoading(true),
          onPageFinished: (_) => _setLoading(false),
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && isReturnUrl(uri)) {
              // Prevented rather than allowed: the return page is ours and has
              // nothing to show. Loading it would flash a blank page over the
              // result screen.
              _finish(uri.queryParameters);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    final redirect = widget.redirectUrl;
    if (redirect != null && redirect.isNotEmpty) {
      _controller.loadRequest(Uri.parse(redirect));
    } else {
      _controller.loadHtmlString(
        buildAutoSubmitForm(widget.actionUrl!, widget.formFields!),
      );
    }
  }

  void _setLoading(bool value) {
    if (mounted && _loading != value) setState(() => _loading = value);
  }

  void _finish(Map<String, String> params) {
    if (_returned) return;
    _returned = true;
    Navigator.of(context).pop(params);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Backing out is a cancellation, not a failure. Popping with null is
        // what tells the caller which of the two happened.
        if (!didPop && !_returned) {
          _returned = true;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel payment',
            onPressed: () {
              if (_returned) return;
              _returned = true;
              Navigator.of(context).pop();
            },
          ),
          bottom: _loading
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(3),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              : null,
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}

/// True once the gateway has sent the shopper back to us.
///
/// Matched against [Env.returnHost] rather than a hardcoded domain. The
/// reference app hardcodes the production host, so a build pointed at staging
/// sits on the payment page forever waiting for a redirect that can never
/// match. The path check stays a `contains` because the providers append their
/// own segments -- /payment/success, /payment/failure, /payment-callback.
bool isReturnUrl(Uri uri) =>
    uri.host == Env.returnHost && uri.path.contains('/payment');

/// A page whose only job is to POST a signed field bag and get out of the way.
///
/// Every key and value is HTML-escaped. These come from the gateway, and a
/// quote in a signed value would otherwise break out of the attribute and
/// corrupt the form -- which the provider would reject as a bad signature.
String buildAutoSubmitForm(String actionUrl, Map<String, dynamic> fields) {
  // Attribute mode, not the default. The default also escapes `/`, which turns
  // an action URL into `https:&#47;&#47;…`. Browsers decode that, but a signed
  // field value mangled the same way is a signature the gateway will reject.
  const escape = HtmlEscape(HtmlEscapeMode.attribute);
  final inputs = StringBuffer();
  for (final entry in fields.entries) {
    inputs.write(
      '<input type="hidden" name="${escape.convert(entry.key)}" '
      'value="${escape.convert('${entry.value}')}">',
    );
  }

  return '<!DOCTYPE html><html><head>'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '</head>'
      '<body onload="document.forms[0].submit()">'
      '<form method="POST" action="${escape.convert(actionUrl)}">$inputs</form>'
      '</body></html>';
}
