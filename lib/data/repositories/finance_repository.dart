import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/models.dart';
import '../../domain/services/csv_data_exchange.dart';
import '../../domain/services/csv_import_service.dart';
import '../../domain/services/household_invite.dart';
import '../../domain/services/money_math.dart';
import '../../domain/services/portfolio_math.dart';
import '../../domain/services/recurrence_period.dart';
import '../../domain/services/supported_currencies.dart';
import '../auth/auth_service.dart';
import '../persistence/firestore_household_cloud_store.dart';
import '../persistence/local_store.dart';
import '../persistence/user_cloud_store.dart';
import '../services/fx_rate_service.dart';
import '../services/household_cloud_store.dart';
import '../services/quote_client.dart';

class FinanceRepository extends ChangeNotifier {
  FinanceRepository({
    LocalStore? store,
    FxRateService? fxService,
    HouseholdCloudStore? householdCloud,
    QuoteClient? quoteClient,
    AuthService? auth,
    UserCloudStore? userCloud,
    this.refreshRatesOnInit = true,
  })  : _store = store ?? LocalStore(),
        _fx = fxService ?? FxRateService(),
        _householdCloud = householdCloud ?? _defaultHouseholdCloud(),
        _injectedQuoteClient = quoteClient,
        _auth = auth ?? const SignedOutAuthService(),
        _userCloud = userCloud ?? const NoOpUserCloudStore() {
    _authSub = _auth.authStateChanges().listen((_) {
      notifyListeners();
    });
  }

  static HouseholdCloudStore _defaultHouseholdCloud() {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirestoreHouseholdCloudStore();
      }
    } catch (_) {
      // Unit tests and hosts without a Firebase plugin.
    }
    return const UnavailableHouseholdCloudStore();
  }

  final LocalStore _store;
  final FxRateService _fx;
  final HouseholdCloudStore _householdCloud;
  final QuoteClient? _injectedQuoteClient;
  final AuthService _auth;
  final UserCloudStore _userCloud;
  final bool refreshRatesOnInit;
  final _uuid = const Uuid();
  static const _quotePause = Duration(milliseconds: 280);
  YahooQuoteClient? _yahooClient;
  CompositeQuoteClient? _compositeClient;
  String? _compositeFinnhubToken;
  String? _compositeAlphaVantageToken;
  String? _compositeTwelveDataToken;

  bool loading = true;
  String? error;
  bool ratesRefreshing = false;
  String? ratesSource;
  DateTime? ratesUpdatedAt;
  String? ratesError;

  bool householdSyncing = false;
  String? householdSyncError;
  String? householdSyncMessage;
  Timer? _householdPushTimer;
  bool _applyingRemote = false;
  bool _applyingUserCloud = false;
  StreamSubscription<AuthUser?>? _authSub;

  bool accountSyncing = false;
  String? accountSyncError;
  String? accountSyncMessage;
  DateTime? snapshotUpdatedAt;
  DateTime? lastCloudSyncedAt;

  late AppSettings settings;
  List<HouseholdProfile> profiles = [];
  List<Account> accounts = [];
  List<SpendCategory> categories = [];
  List<MoneyTransaction> transactions = [];
  List<BudgetCategory> budgets = [];
  List<SavingsGoal> goals = [];
  List<CurrencyRate> rates = [];
  List<InvestmentHolding> holdings = [];
  Map<String, CachedQuote> quotes = {};
  String? finnhubToken;
  String? alphaVantageToken;
  String? twelveDataToken;

  bool quotesRefreshing = false;
  String? quotesError;
  String? quotesSource;
  DateTime? quotesUpdatedAt;

  Future<void> init() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final existing = await _store.load();
      if (existing == null) {
        _seedEmpty();
      } else {
        _hydrate(existing);
      }
      _ensureSupportedCurrencies();
      quotes = await _store.loadQuotes();
      finnhubToken = await _store.loadFinnhubToken();
      alphaVantageToken = await _store.loadAlphaVantageToken();
      twelveDataToken = await _store.loadTwelveDataToken();
      snapshotUpdatedAt = await _store.loadUpdatedAt();
      if (_auth.currentUser != null) {
        await _reconcileUserCloud();
      }
    } catch (e) {
      error = e.toString();
      _seedEmpty();
    } finally {
      loading = false;
      notifyListeners();
    }

    // Online refresh at startup; keep offline defaults if it fails.
    if (refreshRatesOnInit) {
      await refreshRatesOnline();
    }
    if (settings.householdSharingEnabled) {
      await syncHousehold(pullOnly: true);
    }
    if (refreshRatesOnInit && holdings.isNotEmpty) {
      await refreshQuotes();
    }
  }

  void _hydrate(FinanceSnapshot snapshot) {
    settings = snapshot.settings;
    profiles = [...snapshot.profiles];
    accounts = [...snapshot.accounts];
    categories = [...snapshot.categories];
    transactions = [...snapshot.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    budgets = [...snapshot.budgets];
    goals = [...snapshot.goals];
    rates = [...snapshot.rates];
    holdings = [...snapshot.holdings];
  }

  void _seedEmpty() {
    final you = HouseholdProfile.create('You', colorHex: 0xFF0B6E6E);
    final partner = HouseholdProfile.create('Partner', colorHex: 0xFFE39B2E);
    profiles = [you, partner];
    settings = AppSettings(
      mainCurrency: 'USD',
      activeProfileId: you.id,
      onboardingComplete: false,
    );
    rates = FxRateService.defaultRatesFor('USD');
    ratesSource = 'offline defaults (2026-08-02)';
    ratesUpdatedAt = DateTime.now().toUtc();
    categories = _defaultCategories();
    accounts = [];
    transactions = [];
    budgets = [];
    goals = [];
    holdings = [];
  }

  void _ensureSupportedCurrencies() {
    final defaults = FxRateService.defaultRatesFor(settings.mainCurrency);
    final byCode = {for (final r in rates) r.code: r};
    for (final fallback in defaults) {
      byCode.putIfAbsent(fallback.code, () => fallback);
    }
    // Keep main at 1.
    byCode[settings.mainCurrency] = CurrencyRate(
      code: settings.mainCurrency,
      rateToMain: 1,
      updatedAt: byCode[settings.mainCurrency]?.updatedAt,
    );
    rates = [
      for (final code in SupportedCurrencies.codes)
        if (byCode.containsKey(code)) byCode[code]!,
    ];
  }

  Future<bool> refreshRatesOnline() async {
    ratesRefreshing = true;
    ratesError = null;
    notifyListeners();
    try {
      final result = await _fx.fetchRates(mainCurrency: settings.mainCurrency);
      final byCode = {for (final r in result.rates) r.code: r};
      // Preserve any custom currencies not in the feed.
      for (final existing in rates) {
        byCode.putIfAbsent(existing.code, () => existing);
      }
      rates = [
        for (final code in SupportedCurrencies.codes)
          if (byCode.containsKey(code)) byCode[code]!,
      ];
      ratesSource = result.source;
      ratesUpdatedAt = result.fetchedAt;
      await _persist();
      return true;
    } catch (e) {
      ratesError = 'Could not refresh online — using saved/offline rates.';
      notifyListeners();
      return false;
    } finally {
      ratesRefreshing = false;
      notifyListeners();
    }
  }

  List<SpendCategory> _defaultCategories() {
    return [
      SpendCategory.create(
        name: 'Salary',
        iconName: 'payments',
        colorHex: 0xFF6FAE8F,
        isIncome: true,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Other Income',
        iconName: 'south_west',
        colorHex: 0xFF3AAFA9,
        isIncome: true,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Housing',
        iconName: 'home',
        colorHex: 0xFF0B6E6E,
        isIncome: false,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Groceries',
        iconName: 'local_grocery_store',
        colorHex: 0xFF6FAE8F,
        isIncome: false,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Dining',
        iconName: 'restaurant',
        colorHex: 0xFFE39B2E,
        isIncome: false,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Transport',
        iconName: 'directions_car',
        colorHex: 0xFF5C6BC0,
        isIncome: false,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Subscriptions',
        iconName: 'subscriptions',
        colorHex: 0xFFD96B5F,
        isIncome: false,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Health',
        iconName: 'favorite',
        colorHex: 0xFFD96B5F,
        isIncome: false,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Fun',
        iconName: 'celebration',
        colorHex: 0xFFE39B2E,
        isIncome: false,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Savings',
        iconName: 'savings',
        colorHex: 0xFF148F8F,
        isIncome: false,
        isSystem: true,
      ),
    ];
  }

  FinanceSnapshot get snapshot => FinanceSnapshot(
        settings: settings,
        profiles: profiles,
        accounts: accounts,
        categories: categories,
        transactions: transactions,
        budgets: budgets,
        goals: goals,
        rates: rates,
        holdings: holdings,
      );

  AuthUser? get signedInUser => _auth.currentUser;

  bool get cloudAccountsAvailable => _auth.isAvailable;

  bool get _hasUploadableLocal =>
      settings.onboardingComplete ||
      accounts.isNotEmpty ||
      transactions.isNotEmpty ||
      budgets.isNotEmpty ||
      goals.isNotEmpty ||
      holdings.isNotEmpty;

  Future<void> _persist() async {
    await _writeLocalSnapshot();
    notifyListeners();
    if (!_applyingRemote && settings.householdSharingEnabled) {
      _scheduleHouseholdPush();
    }
  }

  Future<void> _writeLocalSnapshot() async {
    snapshotUpdatedAt = DateTime.now().toUtc();
    await _store.save(snapshot, updatedAt: snapshotUpdatedAt);
    if (!_applyingUserCloud) {
      await _pushUserCloudIfSignedIn();
    }
  }

  Future<void> _pushUserCloudIfSignedIn() async {
    final user = _auth.currentUser;
    if (user == null || _applyingUserCloud) return;
    if (!_hasUploadableLocal) return;
    try {
      final updatedAt = snapshotUpdatedAt ?? DateTime.now().toUtc();
      snapshotUpdatedAt = updatedAt;
      await _userCloud.save(user.uid, snapshot, updatedAt: updatedAt);
      lastCloudSyncedAt = updatedAt;
      accountSyncError = null;
    } catch (e) {
      accountSyncError = 'Could not save online: $e';
    }
  }

  Future<void> _reconcileUserCloud() async {
    final user = _auth.currentUser;
    if (user == null) return;
    accountSyncing = true;
    accountSyncError = null;
    notifyListeners();
    try {
      final remote = await _userCloud.load(user.uid);
      if (remote == null) {
        if (_hasUploadableLocal) {
          await _pushUserCloudIfSignedIn();
          accountSyncMessage = 'Uploaded this device to your account';
        }
        return;
      }

      final localUpdated = snapshotUpdatedAt;
      final cloudIsNewer = localUpdated == null ||
          remote.updatedAt.isAfter(localUpdated);
      final shouldApplyCloud = !_hasUploadableLocal || cloudIsNewer;

      if (shouldApplyCloud) {
        _applyingUserCloud = true;
        _hydrate(remote.snapshot);
        _ensureSupportedCurrencies();
        snapshotUpdatedAt = remote.updatedAt.toUtc();
        await _store.save(snapshot, updatedAt: snapshotUpdatedAt);
        lastCloudSyncedAt = snapshotUpdatedAt;
        _applyingUserCloud = false;
        accountSyncMessage = 'Loaded from your account';
      } else {
        await _pushUserCloudIfSignedIn();
        accountSyncMessage = 'Uploaded this device to your account';
      }
    } catch (e) {
      accountSyncError = 'Could not sync online: $e';
    } finally {
      accountSyncing = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    accountSyncError = null;
    accountSyncing = true;
    notifyListeners();
    try {
      await _auth.signInWithGoogle();
    } catch (e) {
      accountSyncError = 'Google sign-in failed: $e';
      accountSyncing = false;
      notifyListeners();
      rethrow;
    }
    await _reconcileUserCloud();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    lastCloudSyncedAt = null;
    accountSyncMessage = null;
    accountSyncError = null;
    notifyListeners();
  }

  QuoteClient get _quoteClient {
    final injected = _injectedQuoteClient;
    if (injected != null) return injected;
    final yahoo = _yahooClient ??= YahooQuoteClient();
    if (_compositeClient == null ||
        _compositeFinnhubToken != finnhubToken ||
        _compositeAlphaVantageToken != alphaVantageToken ||
        _compositeTwelveDataToken != twelveDataToken) {
      _compositeClient = CompositeQuoteClient.fromTokens(
        yahoo: yahoo,
        userToken: finnhubToken,
        alphaVantageUserToken: alphaVantageToken,
        twelveDataUserToken: twelveDataToken,
      );
      _compositeFinnhubToken = finnhubToken;
      _compositeAlphaVantageToken = alphaVantageToken;
      _compositeTwelveDataToken = twelveDataToken;
    }
    return _compositeClient!;
  }

  void _scheduleHouseholdPush() {
    _householdPushTimer?.cancel();
    _householdPushTimer = Timer(const Duration(milliseconds: 900), () {
      unawaited(syncHousehold(pushOnly: true));
    });
  }

  Future<void> completeOnboarding({
    required String mainCurrency,
    required String primaryName,
    String? partnerName,
    required Account starterAccount,
  }) async {
    final you = HouseholdProfile.create(primaryName, colorHex: 0xFF0B6E6E);
    final profilesList = <HouseholdProfile>[you];
    if (partnerName != null && partnerName.trim().isNotEmpty) {
      profilesList.add(
        HouseholdProfile.create(partnerName.trim(), colorHex: 0xFFE39B2E),
      );
    }
    profiles = profilesList;
    settings = AppSettings(
      mainCurrency: mainCurrency,
      activeProfileId: you.id,
      onboardingComplete: true,
    );
    rates = FxRateService.defaultRatesFor(mainCurrency);
    ratesSource = 'offline defaults (2026-08-02)';
    ratesUpdatedAt = DateTime.now().toUtc();
    accounts = [
      Account(
        id: starterAccount.id,
        name: starterAccount.name,
        type: starterAccount.type,
        currencyCode: starterAccount.currencyCode,
        openingBalance: starterAccount.openingBalance,
        ownerProfileId: you.id,
        visibility: starterAccount.visibility,
        includeInNetWorth: starterAccount.includeInNetWorth,
      ),
    ];
    await loadDemoExtras(you.id);
    await _persist();
    await refreshRatesOnline();
  }

  Future<void> loadDemoExtras(String ownerId, {DateTime? now}) async {
    final checking = accounts.first;
    final groceries = categories.firstWhere((c) => c.name == 'Groceries');
    final salary = categories.firstWhere((c) => c.name == 'Salary');
    final subs = categories.firstWhere((c) => c.name == 'Subscriptions');
    final asOf = now ?? DateTime.now();
    final mk = MoneyMath.monthKey(asOf);

    DateTime onOrBeforeToday(int day) {
      final clamped = day > asOf.day ? asOf.day : day;
      return DateTime(asOf.year, asOf.month, clamped);
    }

    transactions = [
      MoneyTransaction.create(
        type: TransactionType.income,
        amount: 4200,
        currencyCode: settings.mainCurrency,
        accountId: checking.id,
        categoryId: salary.id,
        date: onOrBeforeToday(1),
        ownerProfileId: ownerId,
        visibility: VisibilityScope.shared,
        note: 'Monthly salary',
        isRecurring: true,
        recurringLabel: 'Monthly salary',
        recurrencePeriod: RecurrencePeriod.monthly,
      ),
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 86.4,
        currencyCode: settings.mainCurrency,
        accountId: checking.id,
        categoryId: groceries.id,
        date: onOrBeforeToday(3),
        ownerProfileId: ownerId,
        visibility: VisibilityScope.shared,
        note: 'Market run',
      ),
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 15.99,
        currencyCode: settings.mainCurrency,
        accountId: checking.id,
        categoryId: subs.id,
        date: onOrBeforeToday(5),
        ownerProfileId: ownerId,
        visibility: VisibilityScope.private,
        note: 'Streaming',
        isRecurring: true,
        recurringLabel: 'Stream+',
        recurrencePeriod: RecurrencePeriod.monthly,
      ),
    ];

    budgets = [
      BudgetCategory.create(
        categoryId: groceries.id,
        monthKey: mk,
        allocated: 450,
        visibility: VisibilityScope.shared,
        ownerProfileId: ownerId,
      ),
      BudgetCategory.create(
        categoryId: subs.id,
        monthKey: mk,
        allocated: 80,
        visibility: VisibilityScope.shared,
        ownerProfileId: ownerId,
      ),
    ];

    goals = [
      SavingsGoal.create(
        name: 'Emergency fund',
        targetAmount: 5000,
        currentAmount: 1200,
        currencyCode: settings.mainCurrency,
        ownerProfileId: ownerId,
        visibility: VisibilityScope.shared,
      ),
    ];
  }

  Future<void> setActiveProfile(String profileId) async {
    settings = settings.copyWith(activeProfileId: profileId);
    await _persist();
  }

  Future<void> setVisibilityFilters({bool? showShared, bool? showPrivate}) async {
    settings = settings.copyWith(
      showShared: showShared,
      showPrivate: showPrivate,
    );
    await _persist();
  }

  Future<void> setMainCurrency(String code) async {
    settings = settings.copyWith(mainCurrency: code);
    rates = FxRateService.defaultRatesFor(code);
    ratesSource = 'offline defaults (awaiting refresh)';
    await _persist();
    await refreshRatesOnline();
  }

  Future<void> upsertRate(CurrencyRate rate) async {
    final others = rates.where((r) => r.code != rate.code).toList();
    rates = [...others, rate];
    await _persist();
  }

  Future<void> addProfile(String name) async {
    profiles = [...profiles, HouseholdProfile.create(name)];
    await _persist();
  }

  Future<void> updateProfile(HouseholdProfile profile) async {
    profiles = [
      for (final p in profiles)
        if (p.id == profile.id) profile else p,
    ];
    await _persist();
  }

  Future<void> renameActiveProfile(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final current = profiles.where((p) => p.id == settings.activeProfileId);
    if (current.isEmpty) return;
    await updateProfile(current.first.copyWith(name: trimmed));
  }

  /// Wipes all local data and returns the app to onboarding.
  Future<void> clearAllData({bool deleteRemoteHousehold = true}) async {
    _householdPushTimer?.cancel();
    if (deleteRemoteHousehold && settings.householdSharingEnabled) {
      try {
        await _householdCloud.delete(settings.householdCloudId!);
      } catch (_) {
        // Local clear still proceeds if remote delete fails.
      }
    }
    await _store.clear();
    _seedEmpty();
    householdSyncError = null;
    householdSyncMessage = null;
    quotes = {};
    finnhubToken = null;
    alphaVantageToken = null;
    twelveDataToken = null;
    quotesError = null;
    quotesSource = null;
    quotesUpdatedAt = null;
    snapshotUpdatedAt = DateTime.now().toUtc();
    lastCloudSyncedAt = null;
    accountSyncMessage = null;
    accountSyncError = null;
    await _store.save(snapshot, updatedAt: snapshotUpdatedAt);
    notifyListeners();
  }

  HouseholdProfile? get activeProfile {
    for (final p in profiles) {
      if (p.id == settings.activeProfileId) return p;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  String? householdShareLink({Uri? base}) {
    if (!settings.householdSharingEnabled) return null;
    return HouseholdInvite.buildShareLink(
      cloudId: settings.householdCloudId!,
      inviteKey: settings.householdInviteKey!,
      base: base,
    );
  }

  /// Creates (or refreshes) a shareable household cloud document.
  Future<String> enableHouseholdSharing({Uri? base}) async {
    householdSyncing = true;
    householdSyncError = null;
    notifyListeners();
    try {
      final inviteKey = settings.householdInviteKey?.isNotEmpty == true
          ? settings.householdInviteKey!
          : _uuid.v4().replaceAll('-', '').substring(0, 12);
      final updatedAt = DateTime.now().toUtc();
      final doc = HouseholdCloudDocument(
        inviteKey: inviteKey,
        updatedAt: updatedAt,
        snapshot: snapshot.copyWithSettings(
          settings.copyWith(
            householdCloudId: settings.householdCloudId,
            householdInviteKey: inviteKey,
            householdUpdatedAt: updatedAt,
          ),
        ),
      );

      String cloudId;
      if (settings.householdCloudId != null &&
          settings.householdCloudId!.isNotEmpty) {
        cloudId = settings.householdCloudId!;
        try {
          await _householdCloud.update(cloudId, doc.toJson());
        } on StateError {
          cloudId = await _householdCloud.create(doc.toJson());
        }
      } else {
        cloudId = await _householdCloud.create(doc.toJson());
      }

      settings = settings.copyWith(
        householdCloudId: cloudId,
        householdInviteKey: inviteKey,
        householdUpdatedAt: updatedAt,
      );
      _applyingRemote = true;
      await _writeLocalSnapshot();
      _applyingRemote = false;
      householdSyncMessage = 'Household sharing on';
      notifyListeners();
      return HouseholdInvite.buildShareLink(
        cloudId: cloudId,
        inviteKey: inviteKey,
        base: base,
      );
    } catch (e) {
      householdSyncError = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      householdSyncing = false;
      notifyListeners();
    }
  }

  Future<void> disableHouseholdSharing({bool deleteRemote = false}) async {
    _householdPushTimer?.cancel();
    if (deleteRemote && settings.householdCloudId != null) {
      try {
        await _householdCloud.delete(settings.householdCloudId!);
      } catch (_) {}
    }
    settings = settings.copyWith(
      householdCloudId: null,
      householdInviteKey: null,
      householdUpdatedAt: null,
    );
    householdSyncMessage = 'Household sharing off';
    householdSyncError = null;
    _applyingRemote = true;
    await _writeLocalSnapshot();
    _applyingRemote = false;
    notifyListeners();
  }

  /// Joins a household from an invite link / codes and becomes a new member.
  Future<void> joinHousehold({
    required String cloudId,
    required String inviteKey,
    required String displayName,
  }) async {
    householdSyncing = true;
    householdSyncError = null;
    notifyListeners();
    try {
      final raw = await _householdCloud.read(cloudId);
      if (raw == null) {
        throw StateError('Invite link expired or household not found');
      }
      final remote = HouseholdCloudDocument.fromJson(raw);
      if (remote.inviteKey != inviteKey) {
        throw StateError('Invite key does not match this household');
      }

      final name = displayName.trim().isEmpty ? 'Member' : displayName.trim();
      final me = HouseholdProfile.create(name, colorHex: 0xFFE39B2E);
      final remoteSnapshot = remote.snapshot;
      final mergedProfiles = [...remoteSnapshot.profiles, me];

      _applyingRemote = true;
      _hydrate(
        FinanceSnapshot(
          settings: remoteSnapshot.settings.copyWith(
            activeProfileId: me.id,
            onboardingComplete: true,
            householdCloudId: cloudId,
            householdInviteKey: inviteKey,
            householdUpdatedAt: remote.updatedAt,
            showPrivate: true,
            showShared: true,
          ),
          profiles: mergedProfiles,
          accounts: remoteSnapshot.accounts,
          categories: remoteSnapshot.categories,
          transactions: remoteSnapshot.transactions,
          budgets: remoteSnapshot.budgets,
          goals: remoteSnapshot.goals,
          rates: remoteSnapshot.rates,
          holdings: remoteSnapshot.holdings,
        ),
      );
      _ensureSupportedCurrencies();
      await _writeLocalSnapshot();
      _applyingRemote = false;

      // Publish the new member so the host sees them.
      await syncHousehold(pushOnly: true);
      householdSyncMessage = 'Joined household as $name';
    } catch (e) {
      householdSyncError = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      householdSyncing = false;
      notifyListeners();
    }
  }

  /// Pulls and/or pushes the shared household document (last-write-wins).
  Future<void> syncHousehold({
    bool pullOnly = false,
    bool pushOnly = false,
  }) async {
    if (!settings.householdSharingEnabled) return;
    if (householdSyncing && !pushOnly) return;

    householdSyncing = true;
    householdSyncError = null;
    notifyListeners();
    try {
      final cloudId = settings.householdCloudId!;
      final inviteKey = settings.householdInviteKey!;
      final localActive = settings.activeProfileId;
      final localUpdated = settings.householdUpdatedAt;

      if (!pushOnly) {
        final raw = await _householdCloud.read(cloudId);
        if (raw != null) {
          final remote = HouseholdCloudDocument.fromJson(raw);
          if (remote.inviteKey != inviteKey) {
            throw StateError('Remote household invite key mismatch');
          }
          final remoteIsNewer = localUpdated == null ||
              remote.updatedAt.isAfter(localUpdated.add(const Duration(milliseconds: 1)));
          if (remoteIsNewer) {
            final keepActive = remote.snapshot.profiles
                    .any((p) => p.id == localActive)
                ? localActive
                : remote.snapshot.settings.activeProfileId;
            _applyingRemote = true;
            _hydrate(
              FinanceSnapshot(
                settings: remote.snapshot.settings.copyWith(
                  activeProfileId: keepActive,
                  householdCloudId: cloudId,
                  householdInviteKey: inviteKey,
                  householdUpdatedAt: remote.updatedAt,
                  onboardingComplete: true,
                ),
                profiles: remote.snapshot.profiles,
                accounts: remote.snapshot.accounts,
                categories: remote.snapshot.categories,
                transactions: remote.snapshot.transactions,
                budgets: remote.snapshot.budgets,
                goals: remote.snapshot.goals,
                rates: remote.snapshot.rates,
                holdings: remote.snapshot.holdings,
              ),
            );
            _ensureSupportedCurrencies();
            await _writeLocalSnapshot();
            _applyingRemote = false;
            householdSyncMessage = 'Household updated from link';
          }
        }
      }

      if (!pullOnly) {
        final updatedAt = DateTime.now().toUtc();
        final doc = HouseholdCloudDocument(
          inviteKey: inviteKey,
          updatedAt: updatedAt,
          snapshot: snapshot.copyWithSettings(
            settings.copyWith(
              householdCloudId: cloudId,
              householdInviteKey: inviteKey,
              householdUpdatedAt: updatedAt,
            ),
          ),
        );
        try {
          await _householdCloud.update(cloudId, doc.toJson());
        } on StateError {
          final newId = await _householdCloud.create(doc.toJson());
          settings = settings.copyWith(
            householdCloudId: newId,
            householdUpdatedAt: updatedAt,
          );
          householdSyncMessage =
              'Share link refreshed — copy the new link from User';
          _applyingRemote = true;
          await _writeLocalSnapshot();
          _applyingRemote = false;
          householdSyncing = false;
          notifyListeners();
          return;
        }
        settings = settings.copyWith(householdUpdatedAt: updatedAt);
        _applyingRemote = true;
        await _writeLocalSnapshot();
        _applyingRemote = false;
        householdSyncMessage = 'Household synced';
      }
    } catch (e) {
      householdSyncError = e.toString();
    } finally {
      householdSyncing = false;
      notifyListeners();
    }
  }

  Future<void> addAccount(Account account) async {
    accounts = [...accounts, account];
    if (!rates.any((r) => r.code == account.currencyCode)) {
      rates = [
        ...rates,
        CurrencyRate(code: account.currencyCode, rateToMain: 1),
      ];
    }
    await _persist();
  }

  Future<void> updateAccount(Account account) async {
    accounts = [
      for (final a in accounts)
        if (a.id == account.id) account else a,
    ];
    if (!rates.any((r) => r.code == account.currencyCode)) {
      rates = [
        ...rates,
        CurrencyRate(code: account.currencyCode, rateToMain: 1),
      ];
    }
    await _persist();
  }

  Future<void> deleteAccount(String id) async {
    accounts = accounts.where((a) => a.id != id).toList();
    await _persist();
  }

  Future<void> addTransaction(MoneyTransaction tx) async {
    _ensureRateFor(tx.currencyCode);
    transactions = [tx, ...transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    await _persist();
  }

  Future<void> updateTransaction(MoneyTransaction tx) async {
    _ensureRateFor(tx.currencyCode);
    transactions = [
      for (final t in transactions)
        if (t.id == tx.id) tx else t,
    ]..sort((a, b) => b.date.compareTo(a.date));
    await _persist();
  }

  void _ensureRateFor(String code) {
    if (rates.any((r) => r.code == code)) return;
    final defaults = FxRateService.defaultRatesFor(settings.mainCurrency);
    final fallback = defaults.firstWhere(
      (r) => r.code == code,
      orElse: () => CurrencyRate(code: code, rateToMain: 1),
    );
    rates = [...rates, fallback];
  }

  Future<void> deleteTransaction(String id) async {
    transactions = transactions.where((t) => t.id != id).toList();
    await _persist();
  }

  Future<void> upsertBudget(BudgetCategory budget) async {
    final byId = budgets.indexWhere((b) => b.id == budget.id);
    if (byId >= 0) {
      final copy = [...budgets];
      copy[byId] = budget;
      budgets = copy;
      await _persist();
      return;
    }

    final existingIndex = budgets.indexWhere(
      (b) =>
          b.categoryId == budget.categoryId &&
          b.monthKey == budget.monthKey &&
          b.visibility == budget.visibility &&
          b.ownerProfileId == budget.ownerProfileId,
    );
    if (existingIndex >= 0) {
      final copy = [...budgets];
      copy[existingIndex] = budget;
      budgets = copy;
    } else {
      budgets = [...budgets, budget];
    }
    await _persist();
  }

  Future<void> deleteBudget(String id) async {
    budgets = budgets.where((b) => b.id != id).toList();
    await _persist();
  }

  Future<void> addGoal(SavingsGoal goal) async {
    goals = [...goals, goal];
    await _persist();
  }

  Future<void> updateGoal(SavingsGoal goal) async {
    goals = [
      for (final g in goals)
        if (g.id == goal.id) goal else g,
    ];
    await _persist();
  }

  Future<void> updateGoalProgress(String id, double currentAmount) async {
    goals = [
      for (final g in goals)
        if (g.id == id) g.copyWith(currentAmount: currentAmount) else g,
    ];
    await _persist();
  }

  Future<void> deleteGoal(String id) async {
    goals = goals.where((g) => g.id != id).toList();
    await _persist();
  }

  Future<void> addHolding(InvestmentHolding holding) async {
    holdings = [...holdings, holding];
    _ensureRateFor(holding.currencyCode);
    await _persist();
    await refreshQuotes(symbols: [holding.ticker], force: true);
  }

  Future<void> updateHolding(InvestmentHolding holding) async {
    holdings = [
      for (final h in holdings)
        if (h.id == holding.id) holding else h,
    ];
    _ensureRateFor(holding.currencyCode);
    await _persist();
    await refreshQuotes(symbols: [holding.ticker]);
  }

  Future<void> deleteHolding(String id) async {
    holdings = holdings.where((h) => h.id != id).toList();
    await _persist();
  }

  Future<void> setFinnhubToken(String? token) async {
    final trimmed = token?.trim();
    finnhubToken = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    await _store.saveFinnhubToken(finnhubToken);
    notifyListeners();
    if (holdings.isNotEmpty) {
      await refreshQuotes(force: true);
    }
  }

  Future<void> setAlphaVantageToken(String? token) async {
    final trimmed = token?.trim();
    alphaVantageToken = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    await _store.saveAlphaVantageToken(alphaVantageToken);
    notifyListeners();
    if (holdings.isNotEmpty) {
      await refreshQuotes(force: true);
    }
  }

  Future<void> setTwelveDataToken(String? token) async {
    final trimmed = token?.trim();
    twelveDataToken = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    await _store.saveTwelveDataToken(twelveDataToken);
    notifyListeners();
    if (holdings.isNotEmpty) {
      await refreshQuotes(force: true);
    }
  }

  Future<List<TickerSearchResult>> searchTickers(String query) async {
    try {
      return await _quoteClient.search(query);
    } catch (_) {
      return const [];
    }
  }

  Future<void> refreshQuotes({
    Iterable<String>? symbols,
    QuoteHistoryRange range = QuoteHistoryRange.oneMonth,
    bool force = false,
  }) async {
    final tickers = (symbols ?? holdings.map((h) => h.ticker))
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (tickers.isEmpty) return;

    quotesRefreshing = true;
    quotesError = null;
    notifyListeners();

    var fetched = 0;
    String? lastSource;
    final failures = <String>[];
    try {
      for (var i = 0; i < tickers.length; i++) {
        final ticker = tickers[i];
        final cached = quotes[ticker];
        final quoteFresh =
            cached != null && PortfolioMath.quoteIsFresh(cached.fetchedAt);
        if (!force && cached != null && quoteFresh && _historyCacheFresh(cached, range)) {
          lastSource = cached.source;
          continue;
        }
        try {
          final bundle =
              await _quoteClient.fetchChart(ticker, range: range);
          quotes = {
            ...quotes,
            ticker: _mergeQuote(cached, bundle),
          };
          _ensureRateFor(bundle.quote.currency);
          lastSource = bundle.quote.source;
          fetched++;
        } catch (e) {
          failures.add(ticker);
          if (cached == null) {
            quotesError ??= e.toString();
          }
        }
        if (i != tickers.length - 1) {
          await Future<void>.delayed(_quotePause);
        }
      }
      if (fetched > 0) {
        quotesUpdatedAt = DateTime.now().toUtc();
        quotesSource = lastSource;
        if (failures.isEmpty) quotesError = null;
        await _store.saveQuotes(quotes);
      } else if (failures.isNotEmpty && quotes.values.isNotEmpty) {
        quotesError =
            'Could not refresh quotes — showing last saved prices.';
      } else if (failures.isNotEmpty) {
        quotesError = resolveFinnhubToken(userToken: finnhubToken) == null
            ? 'Quotes unavailable. On the website, add a free Finnhub token in Settings.'
            : 'Could not refresh quotes.';
      }
    } finally {
      quotesRefreshing = false;
      notifyListeners();
    }
  }

  CachedQuote _mergeQuote(CachedQuote? previous, QuoteBundle bundle) {
    final next = bundle.quote;
    if (previous == null) return next;
    final history = {...previous.history, ...next.history};
    final fetched = {...previous.historyFetchedAt, ...next.historyFetchedAt};
    final range = bundle.range;
    // A per-minute Alpha Vantage miss omits this range's stamp so retries are
    // not blocked for the whole quote TTL. Do not resurrect a previous stamp.
    if (range != null &&
        !next.historyFetchedAt.containsKey(range.key) &&
        (next.history[range.key]?.length ?? 0) < 2) {
      fetched.remove(range.key);
    }
    return next.copyWith(history: history, historyFetchedAt: fetched);
  }

  /// Skip a network fetch when this range (or a longer cached series) is fresh.
  /// Empty history with a fresh timestamp means we already tried (e.g. Finnhub
  /// 403 + Alpha Vantage daily-quota miss + Twelve Data miss) and should not
  /// burn the 25/day or 8/min limits. Per-minute Alpha Vantage throttles are
  /// not stamped, so they can retry.
  bool _historyCacheFresh(CachedQuote cached, QuoteHistoryRange range) {
    final stored = PortfolioMath.storedHistoryForRange(cached, range);
    if (stored.length >= 2) {
      final at = PortfolioMath.historyFetchedAtForRange(cached, range);
      return at != null && PortfolioMath.quoteIsFresh(at);
    }
    final attempted = cached.historyFetchedAt[range.key];
    return attempted != null && PortfolioMath.quoteIsFresh(attempted);
  }

  CsvFullExportResult exportFullCsv({DateTime? exportedAt}) {
    return CsvDataExchange.exportSnapshot(
      snapshot,
      exportedAt: exportedAt,
    );
  }

  Future<void> replaceSnapshot(FinanceSnapshot next) async {
    _hydrate(next);
    _ensureSupportedCurrencies();
    await _persist();
    notifyListeners();
  }

  Future<CsvFullImportResult> importFullCsv(String csvBody) async {
    final result = CsvDataExchange.importSnapshot(csvBody);
    await replaceSnapshot(result.snapshot);
    return result;
  }

  /// Auto-detects full multi-section export vs bank-style transaction CSV.
  Future<CsvImportOutcome> importCsv(String csvBody) async {
    if (CsvDataExchange.looksLikeFullExport(csvBody)) {
      final full = await importFullCsv(csvBody);
      return CsvImportOutcome.full(full);
    }

    final result = CsvImportService.parse(
      csvBody: csvBody,
      accounts: accounts,
      categories: categories,
      ownerProfileId: settings.activeProfileId,
      defaultCurrency: settings.mainCurrency,
    );
    if (result.transactions.isNotEmpty) {
      transactions = [...result.transactions, ...transactions]
        ..sort((a, b) => b.date.compareTo(a.date));
      await _persist();
    }
    return CsvImportOutcome.transactions(result);
  }

  List<Account> get visibleAccounts => MoneyMath.filterVisible(
        items: accounts.where((a) => !a.archived),
        visibilityOf: (a) => a.visibility,
        ownerOf: (a) => a.ownerProfileId,
        activeProfileId: settings.activeProfileId,
        showShared: settings.showShared,
        showPrivate: settings.showPrivate,
      ).toList();

  List<MoneyTransaction> get visibleTransactions => MoneyMath.filterVisible(
        items: transactions,
        visibilityOf: (t) => t.visibility,
        ownerOf: (t) => t.ownerProfileId,
        activeProfileId: settings.activeProfileId,
        showShared: settings.showShared,
        showPrivate: settings.showPrivate,
      ).toList();

  List<BudgetCategory> get visibleBudgets => MoneyMath.filterVisible(
        items: budgets,
        visibilityOf: (b) => b.visibility,
        ownerOf: (b) => b.ownerProfileId,
        activeProfileId: settings.activeProfileId,
        showShared: settings.showShared,
        showPrivate: settings.showPrivate,
      ).toList();

  List<SavingsGoal> get visibleGoals => MoneyMath.filterVisible(
        items: goals,
        visibilityOf: (g) => g.visibility,
        ownerOf: (g) => g.ownerProfileId,
        activeProfileId: settings.activeProfileId,
        showShared: settings.showShared,
        showPrivate: settings.showPrivate,
      ).toList();

  List<InvestmentHolding> get visibleHoldings => MoneyMath.filterVisible(
        items: holdings,
        visibilityOf: (h) => h.visibility,
        ownerOf: (h) => h.ownerProfileId,
        activeProfileId: settings.activeProfileId,
        showShared: settings.showShared,
        showPrivate: settings.showPrivate,
      ).toList();

  PortfolioTotals get portfolio => PortfolioMath.summarize(
        holdings: visibleHoldings,
        quotes: quotes,
        mainCurrency: settings.mainCurrency,
        rates: rates,
      );

  double get netWorth =>
      MoneyMath.netWorthMain(
        accounts: visibleAccounts,
        transactions: visibleTransactions,
        mainCurrency: settings.mainCurrency,
        rates: rates,
        asOf: DateTime.now(),
      ) +
      PortfolioMath.includedMarketValueMain(
        holdings: visibleHoldings,
        quotes: quotes,
        mainCurrency: settings.mainCurrency,
        rates: rates,
      );

  double availableToSpend([DateTime? date]) {
    final key = MoneyMath.monthKey(date ?? DateTime.now());
    return MoneyMath.availableToSpend(
      transactions: visibleTransactions,
      budgets: visibleBudgets,
      monthKeyValue: key,
      mainCurrency: settings.mainCurrency,
      rates: rates,
    );
  }

  @override
  void dispose() {
    _householdPushTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
