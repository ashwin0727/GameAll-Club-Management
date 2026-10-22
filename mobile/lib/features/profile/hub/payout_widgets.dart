import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/payout_method.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../authentication/auth_widgets.dart';
import '../../onboarding/payout_validation.dart';

class PayoutMethodCard extends StatelessWidget {
  const PayoutMethodCard({
    super.key,
    required this.method,
    required this.busy,
    required this.onMakePrimary,
    required this.onDelete,
    this.onEdit,
  });

  final PayoutMethod method;
  final bool busy;
  final VoidCallback onMakePrimary;
  final VoidCallback onDelete;

  /// When set, an edit button is shown (editing sends the method back for verification).
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isBank = method.type == PayoutMethodType.bank;
    final (label, color) = switch (method.verification) {
      PayoutVerification.verified => ('Verified', tokens.success),
      PayoutVerification.rejected => ('Couldn’t verify', tokens.destructive),
      PayoutVerification.pending => ('Verification pending', tokens.warning),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: method.isPrimary ? tokens.primary.withValues(alpha: 0.5) : tokens.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: tokens.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(isBank ? Icons.account_balance_outlined : Icons.smartphone_outlined,
                    color: tokens.primary, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isBank ? (method.bankName ?? 'Bank account') : 'UPI',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      isBank
                          ? '${PayoutValidators.maskAccountNumber(method.accountNumber)} · ${method.ifsc ?? ''}'
                          : PayoutValidators.maskUpi(method.upiId),
                      style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                    ),
                    Text(method.accountHolderName,
                        style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  onPressed: busy ? null : onEdit,
                  tooltip: 'Edit',
                  icon: Icon(Icons.edit_outlined, color: tokens.textSecondary),
                ),
              IconButton(
                onPressed: busy ? null : onDelete,
                tooltip: 'Remove',
                icon: Icon(Icons.delete_outline, color: tokens.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (method.isPrimary) PayoutPill(label: 'Primary', color: tokens.primary),
              PayoutPill(label: label, color: color),
              if (!method.isPrimary)
                TextButton(
                  onPressed: busy ? null : onMakePrimary,
                  child: const Text('Make primary'),
                ),
            ],
          ),
          if (method.verification == PayoutVerification.rejected) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              (method.verificationNote?.isNotEmpty ?? false)
                  ? method.verificationNote!
                  : 'We couldn’t verify these details. Remove it and add it again.',
              style: TextStyle(fontSize: 12, color: tokens.destructive),
            ),
          ],
        ],
      ),
    );
  }
}

class PayoutPill extends StatelessWidget {
  const PayoutPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Opens the add / edit sheet. Returns true when something was saved.
///
/// [dark] forces the dark treatment the onboarding screens always use; the Profile pages follow the app's theme.
Future<bool> showPayoutMethodSheet(
  BuildContext context, {
  required String facilityId,
  PayoutMethod? method,
  bool dark = false,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PayoutMethodSheet(facilityId: facilityId, method: method, dark: dark),
  );
  return saved == true;
}

/// Bank account / UPI entry, as a bottom sheet.
class PayoutMethodSheet extends ConsumerStatefulWidget {
  const PayoutMethodSheet({super.key, required this.facilityId, this.method, this.dark = false});

  final String facilityId;
  final PayoutMethod? method;
  final bool dark;

  @override
  ConsumerState<PayoutMethodSheet> createState() => _PayoutMethodSheetState();
}

class _PayoutMethodSheetState extends ConsumerState<PayoutMethodSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _holder = TextEditingController(text: widget.method?.accountHolderName ?? '');
  late final _bank = TextEditingController(text: widget.method?.bankName ?? '');
  late final _account = TextEditingController(text: widget.method?.accountNumber ?? '');
  late final _ifsc = TextEditingController(text: widget.method?.ifsc ?? '');
  late final _upi = TextEditingController(text: widget.method?.upiId ?? '');
  late PayoutMethodType _type = widget.method?.type ?? PayoutMethodType.bank;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.method != null;

  @override
  void dispose() {
    _holder.dispose();
    _bank.dispose();
    _account.dispose();
    _ifsc.dispose();
    _upi.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(payoutRepositoryProvider);
    try {
      final isBank = _type == PayoutMethodType.bank;
      if (_editing) {
        final id = widget.method!.id;
        if (isBank) {
          await repo.updateBank(id,
              accountHolderName: _holder.text, bankName: _bank.text, accountNumber: _account.text, ifsc: _ifsc.text);
        } else {
          await repo.updateUpi(id, accountHolderName: _holder.text, upiId: _upi.text);
        }
      } else if (isBank) {
        await repo.addBank(widget.facilityId,
            accountHolderName: _holder.text, bankName: _bank.text, accountNumber: _account.text, ifsc: _ifsc.text);
      } else {
        await repo.addUpi(widget.facilityId, accountHolderName: _holder.text, upiId: _upi.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, stack) {
      debugPrint('Save payout method failed: $e\n$stack');
      if (mounted) setState(() => _error = 'Could not save this payment method. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body(BuildContext context) {
      final tokens = context.tokens;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surface1,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg2),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_editing ? 'Edit payment method' : 'Add a payment method',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _editing
                        ? 'Changing these details sends the method back for verification.'
                        : 'We’ll verify it by hand before the first payout.',
                    style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SegmentedButton<PayoutMethodType>(
                    segments: const [
                      ButtonSegment(value: PayoutMethodType.bank, label: Text('Bank account')),
                      ButtonSegment(value: PayoutMethodType.upi, label: Text('UPI')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    label: 'Account holder name',
                    controller: _holder,
                    textInputAction: TextInputAction.next,
                    validator: PayoutValidators.holderName,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_type == PayoutMethodType.bank) ...[
                    AppTextField(
                      label: 'Bank name',
                      controller: _bank,
                      textInputAction: TextInputAction.next,
                      validator: PayoutValidators.bankName,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _account,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
                      validator: PayoutValidators.accountNumber,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: const InputDecoration(labelText: 'Account number'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _ifsc,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [LengthLimitingTextInputFormatter(11)],
                      validator: PayoutValidators.ifsc,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: const InputDecoration(labelText: 'IFSC code'),
                    ),
                  ] else
                    AppTextField(
                      label: 'UPI ID (name@bank)',
                      controller: _upi,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      validator: PayoutValidators.upiId,
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: tokens.destructive.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(_error!, style: TextStyle(color: tokens.destructive, fontSize: 13)),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  AuthGradientButton(
                    label: _editing ? 'Save changes' : 'Save payment method',
                    loadingLabel: 'Saving…',
                    isLoading: _saving,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!widget.dark) return body(context);
    return Theme(data: AppTheme.dark(), child: Builder(builder: body));
  }
}
