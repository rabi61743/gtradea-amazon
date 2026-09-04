import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/auth_repository.dart';

/// The provider's own sign-in page, hosted in the app.
///
/// The password typed here is Google's, not ours, and it is typed on Google's
/// page: this screen only watches the address bar for the redirect back and
/// hands the whole URL to the caller. The tokens ride in the URL fragment, so
/// the *whole* Uri is returned rather than its query -- see
/// [AuthRepository.completeOAuth], which reads them from there.
class OAuthWebViewScreen extends StatefulWidget {
  const OAuthWebViewScreen({super.key, required this.title, required this.url});

  final String title;
  final Uri url;

  /// Runs the handshake and returns the URL it landed on, or null if the
  /// person backed out before the provider sent them back.
  static Future<Uri?> show(
    BuildContext context, {
    required String title,
    required Uri url,
  }) {
    return Navigator.of(context).push<Uri>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OAuthWebViewScreen(title: title, url: url),
      ),
    );
  }

  @override
  State<OAuthWebViewScreen> createState() => _OAuthWebViewScreenState();
}

class _OAuthWebViewScreenState extends State<OAuthWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  /// Guards the pop: the redirect can fire more than once, and popping twice
  /// would take the sign-in screen with it.
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
            if (uri != null && AuthRepository.isOAuthReturn(uri)) {
              // Prevented rather than allowed: the callback page is ours and
              // has nothing to show. Loading it would flash a blank page over
              // the screen that is about to close anyway.
              _finish(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(widget.url);
  }

  void _setLoading(bool value) {
    if (mounted && _loading != value) setState(() => _loading = value);
  }

  void _finish(Uri uri) {
    if (_returned) return;
    _returned = true;
    Navigator.of(context).pop(uri);
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
            tooltip: 'Cancel sign-in',
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
