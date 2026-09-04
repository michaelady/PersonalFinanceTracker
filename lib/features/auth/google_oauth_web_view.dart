import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../data/auth/identity_toolkit_client.dart';
import '../../theme/zentho_colors.dart';

class GoogleOauthOutcome {
  const GoogleOauthOutcome.token(this.idToken)
      : error = null,
        cancelled = false;

  const GoogleOauthOutcome.error(this.error)
      : idToken = null,
        cancelled = false;

  const GoogleOauthOutcome.cancelled()
      : idToken = null,
        error = null,
        cancelled = true;

  final String? idToken;
  final String? error;
  final bool cancelled;
}

/// In-app Google OAuth using the Firebase web client.
class GoogleOauthWebView extends StatefulWidget {
  const GoogleOauthWebView({super.key, required this.authUri});

  final String authUri;

  static Future<GoogleOauthOutcome?> open(
    BuildContext context, {
    required String authUri,
  }) {
    return Navigator.of(context).push<GoogleOauthOutcome>(
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
  var _ready = false;
  var _done = false;

  static const _chromeUa =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36';

  static const _bridgeJs = '''
(function() {
  function report() {
    try { ZenthoAuth.postMessage(String(location.href)); } catch (e) {}
  }
  report();
  window.addEventListener('hashchange', report);
})();
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    _prepare();
  }

  Future<void> _prepare() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(ZenthoColors.creamMist);
    await _controller.setUserAgent(_chromeUa);
    await _controller.addJavaScriptChannel(
      'ZenthoAuth',
      onMessageReceived: (message) => _handleUrl(message.message),
    );
    await _controller.setNavigationDelegate(
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
        onPageFinished: (url) async {
          _handleUrl(url);
          try {
            await _controller.runJavaScript(_bridgeJs);
          } catch (_) {
            // Page may have navigated away.
          }
        },
      ),
    );
    final cookieManager = WebViewCookieManager();
    final androidCookies = cookieManager.platform;
    final androidController = _controller.platform;
    if (androidCookies is AndroidWebViewCookieManager &&
        androidController is AndroidWebViewController) {
      await androidCookies.setAcceptThirdPartyCookies(androidController, true);
    }
    await _controller.loadRequest(Uri.parse(widget.authUri));
    if (mounted) setState(() => _ready = true);
  }

  void _finish(GoogleOauthOutcome outcome) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(outcome);
  }

  void _handleUrl(String url) {
    if (_done || !mounted) return;
    try {
      final token = googleIdTokenFromRedirect(url);
      if (token == null) return;
      _finish(GoogleOauthOutcome.token(token));
    } catch (e) {
      _finish(GoogleOauthOutcome.error(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in with Google'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _finish(const GoogleOauthOutcome.cancelled()),
        ),
      ),
      body: _ready
          ? WebViewWidget(controller: _controller)
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
