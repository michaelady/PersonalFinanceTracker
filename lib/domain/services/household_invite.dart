import '../models/models.dart';

/// Packed household document stored in [HouseholdCloudStore].
class HouseholdCloudDocument {
  const HouseholdCloudDocument({
    required this.inviteKey,
    required this.updatedAt,
    required this.snapshot,
    this.version = 1,
  });

  final int version;
  final String inviteKey;
  final DateTime updatedAt;
  final FinanceSnapshot snapshot;

  Map<String, dynamic> toJson() => {
        'v': version,
        'inviteKey': inviteKey,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'snapshot': snapshot.toJson(),
      };

  factory HouseholdCloudDocument.fromJson(Map<String, dynamic> json) {
    final updatedRaw = json['updatedAt'] as String?;
    final updatedAt = updatedRaw == null
        ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : DateTime.parse(updatedRaw).toUtc();
    return HouseholdCloudDocument(
      version: (json['v'] as num?)?.toInt() ?? 1,
      inviteKey: json['inviteKey'] as String? ?? '',
      updatedAt: updatedAt,
      snapshot: FinanceSnapshot.fromJson(
        Map<String, dynamic>.from(json['snapshot'] as Map),
      ),
    );
  }
}

/// Helpers for invite links: `?hh=<cloudId>&k=<inviteKey>`.
abstract final class HouseholdInvite {
  static const cloudQueryKey = 'hh';
  static const inviteQueryKey = 'k';
  static const productionBase =
      'https://michaelady.github.io/PersonalFinanceTracker/';

  static Uri? parseInvite(Uri uri) {
    final cloudId = uri.queryParameters[cloudQueryKey]?.trim();
    final inviteKey = uri.queryParameters[inviteQueryKey]?.trim();
    if (cloudId == null ||
        cloudId.isEmpty ||
        inviteKey == null ||
        inviteKey.isEmpty) {
      return null;
    }
    return Uri(
      queryParameters: {
        cloudQueryKey: cloudId,
        inviteQueryKey: inviteKey,
      },
    );
  }

  static String buildShareLink({
    required String cloudId,
    required String inviteKey,
    Uri? base,
  }) {
    final root = base ?? Uri.base;
    final originBase = root.host.isEmpty
        ? Uri.parse(productionBase)
        : root.replace(queryParameters: const {}, fragment: '');
    return originBase.replace(
      queryParameters: {
        cloudQueryKey: cloudId,
        inviteQueryKey: inviteKey,
      },
    ).toString();
  }

  static ({String cloudId, String inviteKey})? parseShareLink(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final invite = parseInvite(uri);
    if (invite == null) return null;
    return (
      cloudId: invite.queryParameters[cloudQueryKey]!,
      inviteKey: invite.queryParameters[inviteQueryKey]!,
    );
  }
}
