import 'package:flutter/foundation.dart';

import '../../domain/models/models.dart';
import '../../domain/services/csv_import_service.dart';
import '../../domain/services/money_math.dart';
import '../persistence/local_store.dart';

class FinanceRepository extends ChangeNotifier {
  FinanceRepository({LocalStore? store}) : _store = store ?? LocalStore();

  final LocalStore _store;

  bool loading = true;
  String? error;

  late AppSettings settings;
  List<HouseholdProfile> profiles = [];
  List<Account> accounts = [];
  List<SpendCategory> categories = [];
  List<MoneyTransaction> transactions = [];
  List<BudgetCategory> budgets = [];
  List<SavingsGoal> goals = [];
  List<CurrencyRate> rates = [];

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
    } catch (e) {
      error = e.toString();
      _seedEmpty();
    } finally {
      loading = false;
      notifyListeners();
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
    rates = [
      const CurrencyRate(code: 'USD', rateToMain: 1),
      const CurrencyRate(code: 'EUR', rateToMain: 1.08),
      const CurrencyRate(code: 'GBP', rateToMain: 1.27),
      const CurrencyRate(code: 'JPY', rateToMain: 0.0067),
    ];
    categories = _defaultCategories();
    accounts = [];
    transactions = [];
    budgets = [];
    goals = [];
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
      );

  Future<void> _persist() async {
    await _store.save(snapshot);
    notifyListeners();
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
    rates = [
      CurrencyRate(code: mainCurrency, rateToMain: 1),
      ...rates.where((r) => r.code != mainCurrency),
    ];
    if (!rates.any((r) => r.code == starterAccount.currencyCode)) {
      rates = [
        ...rates,
        CurrencyRate(code: starterAccount.currencyCode, rateToMain: 1),
      ];
    }
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
  }

  Future<void> loadDemoExtras(String ownerId) async {
    final checking = accounts.first;
    final groceries = categories.firstWhere((c) => c.name == 'Groceries');
    final salary = categories.firstWhere((c) => c.name == 'Salary');
    final subs = categories.firstWhere((c) => c.name == 'Subscriptions');
    final now = DateTime.now();
    final mk = MoneyMath.monthKey(now);

    transactions = [
      MoneyTransaction.create(
        type: TransactionType.income,
        amount: 4200,
        currencyCode: settings.mainCurrency,
        accountId: checking.id,
        categoryId: salary.id,
        date: DateTime(now.year, now.month, 1),
        ownerProfileId: ownerId,
        visibility: VisibilityScope.shared,
        note: 'Monthly salary',
      ),
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 86.4,
        currencyCode: settings.mainCurrency,
        accountId: checking.id,
        categoryId: groceries.id,
        date: DateTime(now.year, now.month, 3),
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
        date: DateTime(now.year, now.month, 5),
        ownerProfileId: ownerId,
        visibility: VisibilityScope.private,
        note: 'Streaming',
        isRecurring: true,
        recurringLabel: 'Stream+',
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
    if (!rates.any((r) => r.code == code)) {
      rates = [...rates, CurrencyRate(code: code, rateToMain: 1)];
    } else {
      rates = [
        for (final r in rates)
          if (r.code == code) CurrencyRate(code: code, rateToMain: 1) else r,
      ];
    }
    await _persist();
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

  Future<void> addTransaction(MoneyTransaction tx) async {
    transactions = [tx, ...transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    await _persist();
  }

  Future<void> deleteTransaction(String id) async {
    transactions = transactions.where((t) => t.id != id).toList();
    await _persist();
  }

  Future<void> upsertBudget(BudgetCategory budget) async {
    final existingIndex = budgets.indexWhere(
      (b) =>
          b.categoryId == budget.categoryId &&
          b.monthKey == budget.monthKey &&
          b.visibility == budget.visibility &&
          b.ownerProfileId == budget.ownerProfileId,
    );
    if (existingIndex >= 0) {
      final copy = [...budgets];
      copy[existingIndex] = budget.copyWith(allocated: budget.allocated);
      budgets = copy;
    } else {
      budgets = [...budgets, budget];
    }
    await _persist();
  }

  Future<void> addGoal(SavingsGoal goal) async {
    goals = [...goals, goal];
    await _persist();
  }

  Future<void> updateGoalProgress(String id, double currentAmount) async {
    goals = [
      for (final g in goals)
        if (g.id == id) g.copyWith(currentAmount: currentAmount) else g,
    ];
    await _persist();
  }

  Future<CsvImportResult> importCsv(String csvBody) async {
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
    return result;
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

  double get netWorth => MoneyMath.netWorthMain(
        accounts: visibleAccounts,
        transactions: visibleTransactions,
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
}
