import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/auth/identity_toolkit_client.dart';
import '../../theme/zentho_colors.dart';

/// In-app Google OAuth using the Firebase web client. Used when the native
/// Google Sign-In plugin cannot run (no Android OAuth client / SHA-1).
class GoogleOauthWebView extends StatefulWidget {
  const GoogleOauthWebView({super.key, required this.authUri});

  final String authUri;

  static Future<String?> open(BuildContext context, {required String authUri}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => GoogleOauthWebView(authUri: authUri),
      ),
    );
  }

  @override
  State<GoogleOauthWebView> createState() => _GoogleOauthWebViewState();
}

class _GoogleOauthWebViewState extends State<GoogleOauthWebView> {
  late final WebViewController _controller;
  var _done = false;

  static const _chromeUa =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ZenthoColors.creamMist)
      ..setUserAgent(_chromeUa)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _handleUrl(url);
          },
          onNavigationRequest: (request) {
            _handleUrl(request.url);
            return NavigationDecision.navigate;
          },
          onPageStarted: _handleUrl,
          onPageFinished: _handleUrl,
        ),
      )
      ..loadRequest(Uri.parse(widget.authUri));
  }

  void _handleUrl(String url) {
    if (_done || !mounted) return;
    try {
      final token = googleIdTokenFromRedirect(url);
      if (token == null) return;
      _done = true;
      Navigator.of(context).pop(token);
    } catch (e) {
      _done = true;
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in with Google'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
