# Privacy policy template (placeholder)

**This is not legal advice.** Adrian must have a real privacy policy reviewed before Play submission. The hosted placeholder is `web/privacy.html` (GitHub Pages: https://michaelady.github.io/PersonalFinanceTracker/privacy.html).

Play Console → Store settings / App content → Privacy policy URL must point at a public page. After you publish the real policy, either:

1. Replace `web/privacy.html` and deploy web, or
2. Host the policy elsewhere and rebuild the app with `--dart-define=PRIVACY_POLICY_URL=https://your-final-url`.

Suggested sections for the final document: who the operator is, what financial and account data is stored, on-device vs Firestore, Google sign-in, third-party APIs (FX and quotes), OCR if used, retention, deletion, children, contact email, and the effective date.
