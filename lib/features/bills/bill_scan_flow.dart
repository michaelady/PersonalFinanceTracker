import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/bill_parser.dart';
import '../../domain/services/ocr_service.dart';
import '../../domain/services/supported_currencies.dart';
import '../../theme/zentho_colors.dart';

/// Entry points for scanning a bill/invoice into expense transactions.
abstract final class BillScanFlow {
  static Future<void> start(BuildContext context) async {
    final repo = context.read<FinanceRepository>();
    if (repo.accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an account first in Settings.')),
      );
      return;
    }

    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose image'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.paste_outlined),
              title: const Text('Paste bill text'),
              subtitle: const Text('Use when OCR is unavailable'),
              onTap: () => Navigator.pop(context, 'paste'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    String? rawText;
    if (source == 'paste') {
      rawText = await _promptPasteText(context);
    } else {
      rawText = await _recognizeFromImage(
        context,
        source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
    }
    if (rawText == null || rawText.trim().isEmpty || !context.mounted) return;

    final parsed = BillParser.parse(
      rawText,
      fallbackCurrency: repo.settings.mainCurrency,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BillReviewScreen(initial: parsed),
      ),
    );
  }

  static Future<String?> _promptPasteText(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste bill text'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Paste receipt or invoice text…',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Parse'),
          ),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (ok != true) return null;
    return text;
  }

  static Future<String?> _recognizeFromImage(
    BuildContext context,
    ImageSource source,
  ) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      if (!context.mounted) return null;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Reading bill text…')),
            ],
          ),
        ),
      );

      final mime = _mimeForPath(file.name);
      String text;
      try {
        text = await OcrService.recognizeImage(bytes, mimeType: mime);
      } catch (_) {
        if (context.mounted) Navigator.of(context).pop();
        if (!context.mounted) return null;
        final fallback = await _promptPasteText(context);
        return fallback;
      }
      if (context.mounted) Navigator.of(context).pop();
      return text;
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read image: $e')),
        );
      }
      return null;
    }
  }

  static String _mimeForPath(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}

class _EditableLine {
  _EditableLine({
    required this.description,
    required this.amount,
    required this.categoryId,
    required this.selected,
  });

  String description;
  double amount;
  String categoryId;
  bool selected;
}

class BillReviewScreen extends StatefulWidget {
  const BillReviewScreen({super.key, required this.initial});

  final ParsedBill initial;

  @override
  State<BillReviewScreen> createState() => _BillReviewScreenState();
}

class _BillReviewScreenState extends State<BillReviewScreen> {
  late String _currency;
  late DateTime _date;
  late String _accountId;
  late VisibilityScope _visibility;
  late List<_EditableLine> _lines;
  late TextEditingController _merchant;

  @override
  void initState() {
    super.initState();
    final repo = context.read<FinanceRepository>();
    final expenseCats =
        repo.categories.where((c) => !c.isIncome).toList(growable: false);
    _currency = SupportedCurrencies.codes.contains(widget.initial.currencyCode)
        ? widget.initial.currencyCode
        : repo.settings.mainCurrency;
    _date = widget.initial.date;
    _accountId = repo.accounts.first.id;
    _visibility = VisibilityScope.shared;
    _merchant = TextEditingController(text: widget.initial.merchant);
    _lines = [
      for (final line in widget.initial.lines)
        _EditableLine(
          description: line.description,
          amount: line.amount,
          categoryId: BillParser.resolveCategoryId(
                line.categoryName,
                expenseCats,
              ) ??
              expenseCats.first.id,
          selected: true,
        ),
    ];
    if (_lines.isEmpty) {
      _lines.add(
        _EditableLine(
          description: widget.initial.merchant,
          amount: widget.initial.total > 0 ? widget.initial.total : 0,
          categoryId: BillParser.resolveCategoryId(
                widget.initial.suggestedCategoryName,
                expenseCats,
              ) ??
              expenseCats.first.id,
          selected: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _merchant.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = context.read<FinanceRepository>();
    final selected = _lines.where((l) => l.selected && l.amount > 0).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one expense line.')),
      );
      return;
    }

    final merchant = _merchant.text.trim();
    for (final line in selected) {
      final note = [
        if (merchant.isNotEmpty) merchant,
        if (line.description.isNotEmpty && line.description != merchant)
          line.description,
      ].join(' · ');
      await repo.addTransaction(
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: line.amount,
          currencyCode: _currency,
          accountId: _accountId,
          categoryId: line.categoryId,
          date: _date,
          ownerProfileId: repo.settings.activeProfileId,
          visibility: _visibility,
          note: note,
        ),
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${selected.length} expense(s) from bill')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final expenseCats =
        repo.categories.where((c) => !c.isIncome).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Review bill')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          Text(
            'Confirm amounts and categories, then add as expenses.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _merchant,
            decoration: const InputDecoration(labelText: 'Merchant / note'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _accountId,
            decoration: const InputDecoration(labelText: 'Account'),
            items: [
              for (final a in repo.accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _accountId = v ?? _accountId),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: [
              for (final code in SupportedCurrencies.codes)
                DropdownMenuItem(value: code, child: Text(code)),
            ],
            onChanged: (v) => setState(() => _currency = v ?? _currency),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<VisibilityScope>(
            // ignore: deprecated_member_use
            value: _visibility,
            decoration: const InputDecoration(labelText: 'Visibility'),
            items: const [
              DropdownMenuItem(
                value: VisibilityScope.shared,
                child: Text('Shared'),
              ),
              DropdownMenuItem(
                value: VisibilityScope.private,
                child: Text('Private'),
              ),
            ],
            onChanged: (v) =>
                setState(() => _visibility = v ?? VisibilityScope.shared),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text(
              '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: 8),
          Text('Line items', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (var i = 0; i < _lines.length; i++) ...[
            _LineEditor(
              line: _lines[i],
              categories: expenseCats,
              onChanged: () => setState(() {}),
              onRemove: _lines.length > 1
                  ? () => setState(() => _lines.removeAt(i))
                  : null,
            ),
            const SizedBox(height: 8),
          ],
          TextButton.icon(
            onPressed: () {
              setState(() {
                _lines.add(
                  _EditableLine(
                    description: 'Item',
                    amount: 0,
                    categoryId: expenseCats.first.id,
                    selected: true,
                  ),
                );
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Add line'),
          ),
          if (widget.initial.rawText.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Raw OCR text'),
              children: [
                SelectableText(
                  widget.initial.rawText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: ZenthoColors.tealDeep,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(
              'Add ${_lines.where((l) => l.selected && l.amount > 0).length} expense(s)',
            ),
          ),
        ),
      ),
    );
  }
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    required this.line,
    required this.categories,
    required this.onChanged,
    this.onRemove,
  });

  final _EditableLine line;
  final List<SpendCategory> categories;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Checkbox(
              value: line.selected,
              activeColor: ZenthoColors.tealDeep,
              onChanged: (v) {
                line.selected = v ?? true;
                onChanged();
              },
            ),
            Expanded(
              child: TextFormField(
                initialValue: line.description,
                decoration: const InputDecoration(labelText: 'Description'),
                onChanged: (v) => line.description = v,
              ),
            ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        Row(
          children: [
            const SizedBox(width: 48),
            Expanded(
              child: TextFormField(
                initialValue: line.amount == 0 ? '' : line.amount.toString(),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
                onChanged: (v) {
                  line.amount = double.tryParse(v.trim()) ?? 0;
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: line.categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  line.categoryId = v;
                  onChanged();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
