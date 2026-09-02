import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/data/services/fx_rate_service.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/budget_forecast.dart';
import 'package:zentho/domain/services/money_math.dart';
import 'package:zentho/domain/services/recurrence_period.dart';

/// Live web QA repro (fresh onboarding, USD, opening 2500, demo seed).
Future<FinanceRepository> qaDemoRepo({
  DateTime? now,
}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = FinanceRepository(refreshRatesOnInit: false);
  await repo.init();
  final you = repo.profiles.first;
  repo.settings = AppSettings(
    mainCurrency: 'USD',
    activeProfileId: you.id,
    onboardingComplete: true,
    showShared: true,
    showPrivate: true,
  );
  repo.rates = [
    const CurrencyRate(code: 'USD', rateToMain: 1),
    const CurrencyRate(code: 'EUR', rateToMain: 1.151393),
  ];
  repo.accounts = [
    Account.create(
      name: 'Checking',
      type: AccountType.checking,
      currencyCode: 'USD',
      ownerProfileId: you.id,
      visibility: VisibilityScope.shared,
      openingBalance: 2500,
    ),
  ];
  await repo.loadDemoExtras(you.id, now: now ?? DateTime(2026, 9, 2));
  repo.loading = false;
  return repo;
}

void main() {
  // Live QA ran on 2026-09-02; grocery was dated the 3rd and dropped from net worth.
  final asOf = DateTime(2026, 9, 2);

  test('demo seed on day 2 includes grocery and subscription in net worth',
      () async {
    final repo = await qaDemoRepo(now: asOf);
    expect(repo.transactions.map((t) => t.date.day).toSet(), isNot(contains(3)));
    expect(
      repo.transactions.every(
        (t) => !DateTime(t.date.year, t.date.month, t.date.day).isAfter(asOf),
      ),
      isTrue,
    );

    final net = MoneyMath.netWorthMain(
      accounts: repo.visibleAccounts,
      transactions: repo.visibleTransactions,
      mainCurrency: 'USD',
      rates: repo.rates,
      asOf: asOf,
    );
    // Live bug: 6700 = opening + salary, skipping −86.40 −15.99.
    expect(net, isNot(closeTo(6700, 0.01)));
    expect(net, closeTo(2500 + 4200 - 86.4 - 15.99, 0.01));
    expect(net, closeTo(6597.61, 0.01));
  });

  test('demo available-to-spend is 4200 − 86.40 − 15.99', () async {
    final repo = await qaDemoRepo(now: asOf);
    expect(
      MoneyMath.availableToSpend(
        transactions: repo.visibleTransactions,
        budgets: repo.visibleBudgets,
        monthKeyValue: '2026-09',
        mainCurrency: 'USD',
        rates: repo.rates,
      ),
      closeTo(4097.61, 0.01),
    );
  });

  test('Home ATS matches Reports cash flow after extra income and expense',
      () async {
    final repo = await qaDemoRepo(now: asOf);
    final housing = repo.categories.firstWhere((c) => c.name == 'Housing');
    final salary = repo.categories.firstWhere((c) => c.name == 'Salary');
    repo.transactions = [
      ...repo.transactions,
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 200,
        currencyCode: 'USD',
        accountId: repo.accounts.first.id,
        categoryId: housing.id,
        ownerProfileId: repo.settings.activeProfileId,
        visibility: VisibilityScope.shared,
        date: asOf,
      ),
      MoneyTransaction.create(
        type: TransactionType.income,
        amount: 1000,
        currencyCode: 'USD',
        accountId: repo.accounts.first.id,
        categoryId: salary.id,
        ownerProfileId: repo.settings.activeProfileId,
        visibility: VisibilityScope.shared,
        date: asOf,
      ),
    ];

    const month = '2026-09';
    final ats = MoneyMath.availableToSpend(
      transactions: repo.visibleTransactions,
      budgets: repo.visibleBudgets,
      monthKeyValue: month,
      mainCurrency: 'USD',
      rates: repo.rates,
    );
    final reports = MoneyMath.incomeInMonthMain(
          transactions: repo.visibleTransactions,
          monthKeyValue: month,
          mainCurrency: 'USD',
          rates: repo.rates,
          includeExpectedRecurring: true,
        ) -
        MoneyMath.expenseInMonthMain(
          transactions: repo.visibleTransactions,
          monthKeyValue: month,
          mainCurrency: 'USD',
          rates: repo.rates,
          includeExpectedRecurring: true,
        );
    expect(ats, closeTo(reports, 0.01));
    expect(ats, closeTo(4897.61, 0.01));
    expect(ats, isNot(closeTo(4893.34, 0.01)));

    final net = MoneyMath.netWorthMain(
      accounts: repo.visibleAccounts,
      transactions: repo.visibleTransactions,
      mainCurrency: 'USD',
      rates: repo.rates,
      asOf: asOf,
    );
    // Live bug: 7500 skipped seeded expenses.
    expect(net, isNot(closeTo(7500, 0.01)));
    expect(net, closeTo(2500 + 4897.61, 0.01));
  });

  test('EUR ATS uses the displayed USD rate, not a leftover USD total',
      () async {
    final repo = await qaDemoRepo(now: asOf);
    final housing = repo.categories.firstWhere((c) => c.name == 'Housing');
    final salary = repo.categories.firstWhere((c) => c.name == 'Salary');
    repo.transactions = [
      ...repo.transactions,
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 200,
        currencyCode: 'USD',
        accountId: repo.accounts.first.id,
        categoryId: housing.id,
        ownerProfileId: repo.settings.activeProfileId,
        visibility: VisibilityScope.shared,
        date: asOf,
      ),
      MoneyTransaction.create(
        type: TransactionType.income,
        amount: 1000,
        currencyCode: 'USD',
        accountId: repo.accounts.first.id,
        categoryId: salary.id,
        ownerProfileId: repo.settings.activeProfileId,
        visibility: VisibilityScope.shared,
        date: asOf,
      ),
    ];
    repo.settings = repo.settings.copyWith(mainCurrency: 'EUR');
    repo.rates = const [
      CurrencyRate(code: 'EUR', rateToMain: 1),
      CurrencyRate(code: 'USD', rateToMain: 0.862813),
    ];

    const month = '2026-09';
    final ats = MoneyMath.availableToSpend(
      transactions: repo.visibleTransactions,
      budgets: repo.visibleBudgets,
      monthKeyValue: month,
      mainCurrency: 'EUR',
      rates: repo.rates,
    );
    // Live UI showed 4201.53; correct per-txn conversion is 4225.71.
    expect(ats, closeTo(4225.71, 0.01));
    expect(ats, isNot(closeTo(4201.53, 0.01)));
  });

  test('hiding private USD subscription changes EUR ATS by that converted amount',
      () async {
    final repo = await qaDemoRepo(now: asOf);
    final housing = repo.categories.firstWhere((c) => c.name == 'Housing');
    final salary = repo.categories.firstWhere((c) => c.name == 'Salary');
    repo.transactions = [
      ...repo.transactions,
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 200,
        currencyCode: 'USD',
        accountId: repo.accounts.first.id,
        categoryId: housing.id,
        ownerProfileId: repo.settings.activeProfileId,
        visibility: VisibilityScope.shared,
        date: asOf,
      ),
      MoneyTransaction.create(
        type: TransactionType.income,
        amount: 1000,
        currencyCode: 'USD',
        accountId: repo.accounts.first.id,
        categoryId: salary.id,
        ownerProfileId: repo.settings.activeProfileId,
        visibility: VisibilityScope.shared,
        date: asOf,
      ),
    ];
    repo.settings = repo.settings.copyWith(mainCurrency: 'EUR');
    repo.rates = const [
      CurrencyRate(code: 'EUR', rateToMain: 1),
      CurrencyRate(code: 'USD', rateToMain: 0.862813),
    ];

    const month = '2026-09';
    double ats() => MoneyMath.availableToSpend(
          transactions: repo.visibleTransactions,
          budgets: repo.visibleBudgets,
          monthKeyValue: month,
          mainCurrency: 'EUR',
          rates: repo.rates,
        );

    final withPrivate = ats();
    final recurringWithPrivate =
        MoneyMath.recurringCandidates(repo.visibleTransactions).length;

    repo.settings = repo.settings.copyWith(showPrivate: false);
    final sharedOnly = ats();
    final recurringShared =
        MoneyMath.recurringCandidates(repo.visibleTransactions).length;

    final hidden = MoneyMath.toMain(
      amount: 15.99,
      currencyCode: 'USD',
      mainCurrency: 'EUR',
      rates: repo.rates,
    );
    expect(sharedOnly - withPrivate, closeTo(hidden, 0.01));
    expect(sharedOnly - withPrivate, closeTo(13.80, 0.01));
    // Live delta was +37.99 because the starting ATS was stale.
    expect(sharedOnly - withPrivate, isNot(closeTo(37.99, 0.01)));

    // Stream+ is the only private recurring item; salary stays visible.
    expect(recurringWithPrivate, 2);
    expect(recurringShared, 1);
  });

  test('assumed monthly income sees the demo salary series after EUR switch',
      () async {
    final repo = await qaDemoRepo(now: asOf);
    repo.settings = repo.settings.copyWith(mainCurrency: 'EUR');
    repo.rates = const [
      CurrencyRate(code: 'EUR', rateToMain: 1),
      CurrencyRate(code: 'USD', rateToMain: 0.862813),
    ];

    final summary = BudgetForecast.project(
      accounts: repo.visibleAccounts,
      transactions: repo.visibleTransactions,
      budgets: repo.visibleBudgets,
      mainCurrency: 'EUR',
      rates: repo.rates,
      horizon: ForecastHorizon.y1,
      recurrence: RecurrencePeriod.monthly,
      now: asOf,
    );

    final salaryEur = MoneyMath.toMain(
      amount: 4200,
      currencyCode: 'USD',
      mainCurrency: 'EUR',
      rates: repo.rates,
    );
    expect(summary.recurringIncomeMonthly, closeTo(salaryEur, 0.01));
    expect(summary.recurringIncomeMonthly, isNot(closeTo(0, 0.01)));
  });

  test('offline EUR defaults still rebase USD when switching main currency', () {
    final rates = FxRateService.defaultRatesFor('EUR');
    expect(rates.firstWhere((r) => r.code == 'EUR').rateToMain, 1);
    expect(rates.firstWhere((r) => r.code == 'USD').rateToMain, isNot(1));
  });
}
