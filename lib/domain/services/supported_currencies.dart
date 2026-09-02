/// Currencies offered throughout Zentho.
abstract final class SupportedCurrencies {
  static const codes = [
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'CAD',
    'AUD',
    'CHF',
    'RON',
  ];

  /// Default rateToMain when main currency is USD.
  /// Values = how many USD one unit of the currency is worth (as of 2026-08-02).
  static const Map<String, double> usdDefaults = {
    'USD': 1.0,
    'EUR': 1.151393,
    'GBP': 1.345935,
    'JPY': 0.006315,
    'CAD': 0.713364,
    'AUD': 0.702055,
    'CHF': 1.237569,
    'RON': 0.219213,
  };

  /// ISO-4217 minor units. JPY has no cents; the others in [codes] use 2.
  static int fractionDigits(String currencyCode) =>
      currencyCode == 'JPY' ? 0 : 2;
}
