/// Public legal URLs shown in the Android/iOS/web clients.
///
/// The default privacy URL is a hosted **placeholder**. Replace it with a
/// lawyer-reviewed policy before Play review (Play Console Data safety +
/// Store listing). Override at build time with:
/// `--dart-define=PRIVACY_POLICY_URL=https://example.com/privacy`.
abstract final class ZenthoLegal {
  static const privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue:
        'https://michaelady.github.io/PersonalFinanceTracker/privacy.html',
  );

  static final Uri privacyPolicyUri = Uri.parse(privacyPolicyUrl);
}
