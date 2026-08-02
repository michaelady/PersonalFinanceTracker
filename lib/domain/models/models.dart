import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../services/recurrence_period.dart';

const _uuid = Uuid();
const Object _copyKeep = Object();

enum VisibilityScope { shared, private }

enum AccountType { cash, checking, savings, credit, investment, other }

enum TransactionType { income, expense, transfer }

enum GoalStatus { active, completed, paused }

class HouseholdProfile extends Equatable {
  const HouseholdProfile({
    required this.id,
    required this.name,
    this.colorHex = 0xFF0B6E6E,
  });

  final String id;
  final String name;
  final int colorHex;

  factory HouseholdProfile.create(String name, {int colorHex = 0xFF0B6E6E}) {
    return HouseholdProfile(id: _uuid.v4(), name: name, colorHex: colorHex);
  }

  HouseholdProfile copyWith({String? name, int? colorHex}) {
    return HouseholdProfile(
      id: id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorHex': colorHex,
      };

  factory HouseholdProfile.fromJson(Map<String, dynamic> json) {
    return HouseholdProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      colorHex: json['colorHex'] as int? ?? 0xFF0B6E6E,
    );
  }

  @override
  List<Object?> get props => [id, name, colorHex];
}

class CurrencyRate extends Equatable {
  const CurrencyRate({
    required this.code,
    required this.rateToMain,
    this.updatedAt,
  });

  /// Units of this currency per 1 unit of main currency inverted:
  /// amountInMain = amount * rateToMain
  /// where rateToMain means "1 UNIT of this currency = rateToMain MAIN".
  final String code;
  final double rateToMain;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'code': code,
        'rateToMain': rateToMain,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory CurrencyRate.fromJson(Map<String, dynamic> json) {
    return CurrencyRate(
      code: json['code'] as String,
      rateToMain: (json['rateToMain'] as num).toDouble(),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [code, rateToMain, updatedAt];
}

class Account extends Equatable {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.currencyCode,
    required this.openingBalance,
    required this.ownerProfileId,
    required this.visibility,
    this.includeInNetWorth = true,
    this.archived = false,
  });

  final String id;
  final String name;
  final AccountType type;
  final String currencyCode;
  final double openingBalance;
  final String ownerProfileId;
  final VisibilityScope visibility;
  final bool includeInNetWorth;
  final bool archived;

  factory Account.create({
    required String name,
    required AccountType type,
    required String currencyCode,
    required String ownerProfileId,
    required VisibilityScope visibility,
    double openingBalance = 0,
    bool includeInNetWorth = true,
  }) {
    return Account(
      id: _uuid.v4(),
      name: name,
      type: type,
      currencyCode: currencyCode,
      openingBalance: openingBalance,
      ownerProfileId: ownerProfileId,
      visibility: visibility,
      includeInNetWorth: includeInNetWorth,
    );
  }

  Account copyWith({
    String? name,
    AccountType? type,
    String? currencyCode,
    double? openingBalance,
    VisibilityScope? visibility,
    bool? includeInNetWorth,
    bool? archived,
  }) {
    return Account(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      currencyCode: currencyCode ?? this.currencyCode,
      openingBalance: openingBalance ?? this.openingBalance,
      ownerProfileId: ownerProfileId,
      visibility: visibility ?? this.visibility,
      includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'currencyCode': currencyCode,
        'openingBalance': openingBalance,
        'ownerProfileId': ownerProfileId,
        'visibility': visibility.name,
        'includeInNetWorth': includeInNetWorth,
        'archived': archived,
      };

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      name: json['name'] as String,
      type: AccountType.values.byName(json['type'] as String),
      currencyCode: json['currencyCode'] as String,
      openingBalance: (json['openingBalance'] as num).toDouble(),
      ownerProfileId: json['ownerProfileId'] as String,
      visibility: VisibilityScope.values.byName(json['visibility'] as String),
      includeInNetWorth: json['includeInNetWorth'] as bool? ?? true,
      archived: json['archived'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        type,
        currencyCode,
        openingBalance,
        ownerProfileId,
        visibility,
        includeInNetWorth,
        archived,
      ];
}

class SpendCategory extends Equatable {
  const SpendCategory({
    required this.id,
    required this.name,
    required this.iconName,
    required this.colorHex,
    required this.isIncome,
    this.isSystem = false,
  });

  final String id;
  final String name;
  final String iconName;
  final int colorHex;
  final bool isIncome;
  final bool isSystem;

  factory SpendCategory.create({
    required String name,
    required String iconName,
    required int colorHex,
    required bool isIncome,
    bool isSystem = false,
  }) {
    return SpendCategory(
      id: _uuid.v4(),
      name: name,
      iconName: iconName,
      colorHex: colorHex,
      isIncome: isIncome,
      isSystem: isSystem,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconName': iconName,
        'colorHex': colorHex,
        'isIncome': isIncome,
        'isSystem': isSystem,
      };

  factory SpendCategory.fromJson(Map<String, dynamic> json) {
    return SpendCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      iconName: json['iconName'] as String,
      colorHex: json['colorHex'] as int,
      isIncome: json['isIncome'] as bool,
      isSystem: json['isSystem'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, name, iconName, colorHex, isIncome, isSystem];
}

class MoneyTransaction extends Equatable {
  const MoneyTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.currencyCode,
    required this.accountId,
    required this.categoryId,
    required this.date,
    required this.ownerProfileId,
    required this.visibility,
    this.note = '',
    this.transferAccountId,
    this.exchangeRateToMain,
    this.isRecurring = false,
    this.recurringLabel,
    this.recurrencePeriod = RecurrencePeriod.monthly,
  });

  final String id;
  final TransactionType type;
  final double amount;
  final String currencyCode;
  final String accountId;
  final String? categoryId;
  final DateTime date;
  final String ownerProfileId;
  final VisibilityScope visibility;
  final String note;
  final String? transferAccountId;
  final double? exchangeRateToMain;
  final bool isRecurring;
  final String? recurringLabel;
  final RecurrencePeriod recurrencePeriod;

  factory MoneyTransaction.create({
    required TransactionType type,
    required double amount,
    required String currencyCode,
    required String accountId,
    required String ownerProfileId,
    required VisibilityScope visibility,
    String? categoryId,
    DateTime? date,
    String note = '',
    String? transferAccountId,
    double? exchangeRateToMain,
    bool isRecurring = false,
    String? recurringLabel,
    RecurrencePeriod recurrencePeriod = RecurrencePeriod.monthly,
  }) {
    return MoneyTransaction(
      id: _uuid.v4(),
      type: type,
      amount: amount,
      currencyCode: currencyCode,
      accountId: accountId,
      categoryId: categoryId,
      date: date ?? DateTime.now(),
      ownerProfileId: ownerProfileId,
      visibility: visibility,
      note: note,
      transferAccountId: transferAccountId,
      exchangeRateToMain: exchangeRateToMain,
      isRecurring: isRecurring,
      recurringLabel: recurringLabel,
      recurrencePeriod: recurrencePeriod,
    );
  }

  MoneyTransaction copyWith({
    TransactionType? type,
    double? amount,
    String? currencyCode,
    String? accountId,
    String? categoryId,
    DateTime? date,
    VisibilityScope? visibility,
    String? note,
    String? transferAccountId,
    double? exchangeRateToMain,
    bool? isRecurring,
    Object? recurringLabel = _copyKeep,
    RecurrencePeriod? recurrencePeriod,
  }) {
    return MoneyTransaction(
      id: id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      currencyCode: currencyCode ?? this.currencyCode,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      ownerProfileId: ownerProfileId,
      visibility: visibility ?? this.visibility,
      note: note ?? this.note,
      transferAccountId: transferAccountId ?? this.transferAccountId,
      exchangeRateToMain: exchangeRateToMain ?? this.exchangeRateToMain,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringLabel: identical(recurringLabel, _copyKeep)
          ? this.recurringLabel
          : recurringLabel as String?,
      recurrencePeriod: recurrencePeriod ?? this.recurrencePeriod,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'currencyCode': currencyCode,
        'accountId': accountId,
        'categoryId': categoryId,
        'date': date.toIso8601String(),
        'ownerProfileId': ownerProfileId,
        'visibility': visibility.name,
        'note': note,
        'transferAccountId': transferAccountId,
        'exchangeRateToMain': exchangeRateToMain,
        'isRecurring': isRecurring,
        'recurringLabel': recurringLabel,
        'recurrencePeriod': recurrencePeriod.name,
      };

  factory MoneyTransaction.fromJson(Map<String, dynamic> json) {
    return MoneyTransaction(
      id: json['id'] as String,
      type: TransactionType.values.byName(json['type'] as String),
      amount: (json['amount'] as num).toDouble(),
      currencyCode: json['currencyCode'] as String,
      accountId: json['accountId'] as String,
      categoryId: json['categoryId'] as String?,
      date: DateTime.parse(json['date'] as String),
      ownerProfileId: json['ownerProfileId'] as String,
      visibility: VisibilityScope.values.byName(json['visibility'] as String),
      note: json['note'] as String? ?? '',
      transferAccountId: json['transferAccountId'] as String?,
      exchangeRateToMain: (json['exchangeRateToMain'] as num?)?.toDouble(),
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurringLabel: json['recurringLabel'] as String?,
      recurrencePeriod:
          RecurrencePeriod.tryParse(json['recurrencePeriod'] as String?),
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        amount,
        currencyCode,
        accountId,
        categoryId,
        date,
        ownerProfileId,
        visibility,
        note,
        transferAccountId,
        exchangeRateToMain,
        isRecurring,
        recurringLabel,
        recurrencePeriod,
      ];
}

class BudgetCategory extends Equatable {
  const BudgetCategory({
    required this.id,
    required this.categoryId,
    required this.monthKey,
    required this.allocated,
    required this.visibility,
    required this.ownerProfileId,
    this.rollover = true,
  });

  final String id;
  final String categoryId;
  /// Format: yyyy-MM
  final String monthKey;
  final double allocated;
  final VisibilityScope visibility;
  final String ownerProfileId;
  final bool rollover;

  factory BudgetCategory.create({
    required String categoryId,
    required String monthKey,
    required double allocated,
    required VisibilityScope visibility,
    required String ownerProfileId,
    bool rollover = true,
  }) {
    return BudgetCategory(
      id: _uuid.v4(),
      categoryId: categoryId,
      monthKey: monthKey,
      allocated: allocated,
      visibility: visibility,
      ownerProfileId: ownerProfileId,
      rollover: rollover,
    );
  }

  BudgetCategory copyWith({
    String? categoryId,
    String? monthKey,
    double? allocated,
    VisibilityScope? visibility,
    bool? rollover,
  }) {
    return BudgetCategory(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      monthKey: monthKey ?? this.monthKey,
      allocated: allocated ?? this.allocated,
      visibility: visibility ?? this.visibility,
      ownerProfileId: ownerProfileId,
      rollover: rollover ?? this.rollover,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'monthKey': monthKey,
        'allocated': allocated,
        'visibility': visibility.name,
        'ownerProfileId': ownerProfileId,
        'rollover': rollover,
      };

  factory BudgetCategory.fromJson(Map<String, dynamic> json) {
    return BudgetCategory(
      id: json['id'] as String,
      categoryId: json['categoryId'] as String,
      monthKey: json['monthKey'] as String,
      allocated: (json['allocated'] as num).toDouble(),
      visibility: VisibilityScope.values.byName(json['visibility'] as String),
      ownerProfileId: json['ownerProfileId'] as String,
      rollover: json['rollover'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props =>
      [id, categoryId, monthKey, allocated, visibility, ownerProfileId, rollover];
}

class SavingsGoal extends Equatable {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.currencyCode,
    required this.ownerProfileId,
    required this.visibility,
    required this.status,
    this.targetDate,
  });

  final String id;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final String currencyCode;
  final String ownerProfileId;
  final VisibilityScope visibility;
  final GoalStatus status;
  final DateTime? targetDate;

  double get progress =>
      targetAmount <= 0 ? 0 : (currentAmount / targetAmount).clamp(0, 1);

  factory SavingsGoal.create({
    required String name,
    required double targetAmount,
    required String currencyCode,
    required String ownerProfileId,
    required VisibilityScope visibility,
    double currentAmount = 0,
    DateTime? targetDate,
  }) {
    return SavingsGoal(
      id: _uuid.v4(),
      name: name,
      targetAmount: targetAmount,
      currentAmount: currentAmount,
      currencyCode: currencyCode,
      ownerProfileId: ownerProfileId,
      visibility: visibility,
      status: GoalStatus.active,
      targetDate: targetDate,
    );
  }

  SavingsGoal copyWith({
    String? name,
    double? targetAmount,
    double? currentAmount,
    String? currencyCode,
    VisibilityScope? visibility,
    GoalStatus? status,
    DateTime? targetDate,
  }) {
    return SavingsGoal(
      id: id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      currencyCode: currencyCode ?? this.currencyCode,
      ownerProfileId: ownerProfileId,
      visibility: visibility ?? this.visibility,
      status: status ?? this.status,
      targetDate: targetDate ?? this.targetDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'targetAmount': targetAmount,
        'currentAmount': currentAmount,
        'currencyCode': currencyCode,
        'ownerProfileId': ownerProfileId,
        'visibility': visibility.name,
        'status': status.name,
        'targetDate': targetDate?.toIso8601String(),
      };

  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    return SavingsGoal(
      id: json['id'] as String,
      name: json['name'] as String,
      targetAmount: (json['targetAmount'] as num).toDouble(),
      currentAmount: (json['currentAmount'] as num).toDouble(),
      currencyCode: json['currencyCode'] as String,
      ownerProfileId: json['ownerProfileId'] as String,
      visibility: VisibilityScope.values.byName(json['visibility'] as String),
      status: GoalStatus.values.byName(json['status'] as String),
      targetDate: json['targetDate'] == null
          ? null
          : DateTime.parse(json['targetDate'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        targetAmount,
        currentAmount,
        currencyCode,
        ownerProfileId,
        visibility,
        status,
        targetDate,
      ];
}

class AppSettings extends Equatable {
  const AppSettings({
    required this.mainCurrency,
    required this.activeProfileId,
    required this.onboardingComplete,
    this.showPrivate = true,
    this.showShared = true,
    this.householdCloudId,
    this.householdInviteKey,
    this.householdUpdatedAt,
  });

  final String mainCurrency;
  final String activeProfileId;
  final bool onboardingComplete;
  final bool showPrivate;
  final bool showShared;

  /// Remote household document id (jsonblob) when sharing is enabled.
  final String? householdCloudId;

  /// Secret required to join / write the shared household.
  final String? householdInviteKey;

  /// Last known household document revision timestamp (UTC).
  final DateTime? householdUpdatedAt;

  bool get householdSharingEnabled =>
      householdCloudId != null &&
      householdCloudId!.isNotEmpty &&
      householdInviteKey != null &&
      householdInviteKey!.isNotEmpty;

  AppSettings copyWith({
    String? mainCurrency,
    String? activeProfileId,
    bool? onboardingComplete,
    bool? showPrivate,
    bool? showShared,
    Object? householdCloudId = _copyKeep,
    Object? householdInviteKey = _copyKeep,
    Object? householdUpdatedAt = _copyKeep,
  }) {
    return AppSettings(
      mainCurrency: mainCurrency ?? this.mainCurrency,
      activeProfileId: activeProfileId ?? this.activeProfileId,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      showPrivate: showPrivate ?? this.showPrivate,
      showShared: showShared ?? this.showShared,
      householdCloudId: identical(householdCloudId, _copyKeep)
          ? this.householdCloudId
          : householdCloudId as String?,
      householdInviteKey: identical(householdInviteKey, _copyKeep)
          ? this.householdInviteKey
          : householdInviteKey as String?,
      householdUpdatedAt: identical(householdUpdatedAt, _copyKeep)
          ? this.householdUpdatedAt
          : householdUpdatedAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() => {
        'mainCurrency': mainCurrency,
        'activeProfileId': activeProfileId,
        'onboardingComplete': onboardingComplete,
        'showPrivate': showPrivate,
        'showShared': showShared,
        'householdCloudId': householdCloudId,
        'householdInviteKey': householdInviteKey,
        'householdUpdatedAt': householdUpdatedAt?.toIso8601String(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      mainCurrency: json['mainCurrency'] as String,
      activeProfileId: json['activeProfileId'] as String,
      onboardingComplete: json['onboardingComplete'] as bool? ?? false,
      showPrivate: json['showPrivate'] as bool? ?? true,
      showShared: json['showShared'] as bool? ?? true,
      householdCloudId: json['householdCloudId'] as String?,
      householdInviteKey: json['householdInviteKey'] as String?,
      householdUpdatedAt: json['householdUpdatedAt'] == null
          ? null
          : DateTime.tryParse(json['householdUpdatedAt'] as String)?.toUtc(),
    );
  }

  @override
  List<Object?> get props => [
        mainCurrency,
        activeProfileId,
        onboardingComplete,
        showPrivate,
        showShared,
        householdCloudId,
        householdInviteKey,
        householdUpdatedAt,
      ];
}

class FinanceSnapshot extends Equatable {
  const FinanceSnapshot({
    required this.settings,
    required this.profiles,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.budgets,
    required this.goals,
    required this.rates,
  });

  final AppSettings settings;
  final List<HouseholdProfile> profiles;
  final List<Account> accounts;
  final List<SpendCategory> categories;
  final List<MoneyTransaction> transactions;
  final List<BudgetCategory> budgets;
  final List<SavingsGoal> goals;
  final List<CurrencyRate> rates;

  FinanceSnapshot copyWithSettings(AppSettings settings) {
    return FinanceSnapshot(
      settings: settings,
      profiles: profiles,
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      budgets: budgets,
      goals: goals,
      rates: rates,
    );
  }

  Map<String, dynamic> toJson() => {
        'settings': settings.toJson(),
        'profiles': profiles.map((e) => e.toJson()).toList(),
        'accounts': accounts.map((e) => e.toJson()).toList(),
        'categories': categories.map((e) => e.toJson()).toList(),
        'transactions': transactions.map((e) => e.toJson()).toList(),
        'budgets': budgets.map((e) => e.toJson()).toList(),
        'goals': goals.map((e) => e.toJson()).toList(),
        'rates': rates.map((e) => e.toJson()).toList(),
      };

  factory FinanceSnapshot.fromJson(Map<String, dynamic> json) {
    return FinanceSnapshot(
      settings: AppSettings.fromJson(json['settings'] as Map<String, dynamic>),
      profiles: (json['profiles'] as List)
          .map((e) => HouseholdProfile.fromJson(e as Map<String, dynamic>))
          .toList(),
      accounts: (json['accounts'] as List)
          .map((e) => Account.fromJson(e as Map<String, dynamic>))
          .toList(),
      categories: (json['categories'] as List)
          .map((e) => SpendCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
      transactions: (json['transactions'] as List)
          .map((e) => MoneyTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      budgets: (json['budgets'] as List)
          .map((e) => BudgetCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
      goals: (json['goals'] as List)
          .map((e) => SavingsGoal.fromJson(e as Map<String, dynamic>))
          .toList(),
      rates: (json['rates'] as List)
          .map((e) => CurrencyRate.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [
        settings,
        profiles,
        accounts,
        categories,
        transactions,
        budgets,
        goals,
        rates,
      ];
}
