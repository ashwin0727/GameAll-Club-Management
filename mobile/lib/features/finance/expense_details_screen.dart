import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import 'edit_expense_sheet.dart';
import 'finance_presentation.dart';
import 'mark_expense_paid_sheet.dart';

/// Finance → Expenses → one expense — mirrors
/// src/features/finance/components/expense-details-page.tsx.
class ExpenseDetailsScreen extends ConsumerStatefulWidget {
  const ExpenseDetailsScreen({super.key, required this.expenseId});

  final String expenseId;

  @override
  ConsumerState<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends ConsumerState<ExpenseDetailsScreen> {
  ExpenseDetail? _expense;
  String? _receiptUrl;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      final detail = await repo.getExpense(widget.expenseId);
      String? url;
      if (detail?.receiptPath != null) {
        url = await repo.signedExpenseReceiptUrl(detail!.receiptPath);
      }
      if (!mounted) return;
      setState(() {
        _expense = detail;
        _receiptUrl = url;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _void() async {
    final expense = _expense;
    if (expense == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void this expense?'),
        content: Text(
          'The ${financeAmount(expense.amountMinor)} ${expense.categoryName} expense stays on the books, marked void.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Void')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(financeRepositoryProvider).voidExpense(expense.id);
      await _load();
    } on AppException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markPaid() async {
    final expense = _expense;
    if (expense == null) return;
    final row = ExpenseRow(
      id: expense.id,
      categoryId: expense.categoryId,
      categoryName: expense.categoryName,
      amountMinor: expense.amountMinor,
      amountPaidMinor: expense.amountPaidMinor,
      currency: expense.currency,
      paymentMethod: expense.paymentMethod,
      paymentStatus: expense.paymentStatus,
      spentOn: expense.spentOn,
      dueOn: expense.dueOn,
      vendor: expense.vendor,
      reference: expense.reference,
      notes: expense.notes,
      receiptPath: expense.receiptPath,
      status: expense.status,
      createdByName: expense.createdByName,
    );
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MarkExpensePaidSheet(expense: row),
    );
    if (done == true) _load();
  }

  Future<void> _edit() async {
    final expense = _expense;
    if (expense == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditExpenseSheet(expense: expense),
    );
    if (saved == true) _load();
  }

  StatusTone _tone(ExpensePaymentStatus s) => switch (s) {
        ExpensePaymentStatus.paid => StatusTone.success,
        ExpensePaymentStatus.partial => StatusTone.warning,
        ExpensePaymentStatus.pending => StatusTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expense')),
      body: SafeArea(
        child: _loading
            ? const _ExpenseDetailsSkeleton()
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : _expense == null
                    ? const EmptyStateView(
                        title: 'Not found',
                        message: 'This expense could not be found.',
                      )
                    : _body(_expense!),
      ),
    );
  }

  Widget _body(ExpenseDetail e) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.vendor ?? e.categoryName, style: AppTypography.rowTitle(context)),
                    Text('${e.categoryName} · ${Formatters.dateShort(DateTime.parse(e.spentOn))}',
                        style: AppTypography.caption(context)),
                  ],
                ),
              ),
              e.isVoid
                  ? const StatusBadge(label: 'Void', tone: StatusTone.neutral)
                  : StatusBadge(label: e.paymentStatus.label, tone: _tone(e.paymentStatus)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                _row('Amount', financeAmount(e.amountMinor)),
                _row('Paid', financeAmount(e.amountPaidMinor)),
                if (e.outstandingMinor > 0)
                  _row('Outstanding', financeAmount(e.outstandingMinor), tone: AppColors.warning),
                _row('Tax / GST', e.taxMinor != null ? financeAmount(e.taxMinor!) : '—'),
                _row('Payment method', e.paymentMethod ?? '—'),
                _row('Due date', e.dueOn != null ? Formatters.dateShort(DateTime.parse(e.dueOn!)) : '—'),
                _row('Vendor / Payee', e.vendor ?? '—'),
                _row('Reference', e.reference ?? '—'),
                _row('Recorded by', e.createdByName ?? '—'),
              ],
            ),
          ),
          if (e.notes != null && e.notes!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notes', style: AppTypography.caption(context)),
                  const SizedBox(height: 2),
                  Text(e.notes!),
                ],
              ),
            ),
          ],
          if (e.voidReason != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Void reason: ${e.voidReason}', style: AppTypography.caption(context)),
          ],
          if (e.sourceMaintenanceTicketId != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Posted from a maintenance ticket.', style: AppTypography.caption(context)),
          ],
          if (_receiptUrl != null) ...[
            const SizedBox(height: AppSpacing.sm),
            GhostButton(
              label: 'View receipt',
              onPressed: () => launchUrl(Uri.parse(_receiptUrl!), mode: LaunchMode.externalApplication),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text('Payment history', style: AppTypography.rowTitle(context)),
          const SizedBox(height: AppSpacing.sm),
          if (e.payments.isEmpty)
            Text('No payments recorded yet.', style: AppTypography.secondary(context))
          else
            ...e.payments.map((p) => AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(financeAmount(p.amountMinor),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              '${Formatters.dateShort(DateTime.parse(p.paidOn))}'
                              '${p.paymentMethod != null ? ' · ${p.paymentMethod}' : ''}',
                              style: AppTypography.caption(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          if (!e.isVoid) ...[
            const SizedBox(height: AppSpacing.lg),
            if (e.paymentStatus != ExpensePaymentStatus.paid)
              PrimaryButton(
                label: 'Mark paid',
                isLoading: false,
                onPressed: _busy ? null : _markPaid,
              ),
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(label: 'Edit', onPressed: _busy ? null : _edit),
            const SizedBox(height: AppSpacing.sm),
            DangerButton(label: 'Void expense', onPressed: _busy ? null : _void),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? tone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppTypography.caption(context))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: tone)),
        ],
      ),
    );
  }
}

/// Structure-shaped placeholder shown while the expense detail loads —
/// header row + badge, a key-value detail card, then payment-history rows.
class _ExpenseDetailsSkeleton extends StatelessWidget {
  const _ExpenseDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: const [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeleton(width: 160, height: 17),
                  SizedBox(height: AppSpacing.sm),
                  AppSkeleton(width: 120, height: 12),
                ],
              ),
            ),
            AppSkeleton(width: 56, height: 22, radius: AppRadius.pill),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        SkeletonCard(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 13),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 13),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        AppSkeleton(width: 140, height: 16),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(trailing: false),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(trailing: false),
      ],
    );
  }
}
