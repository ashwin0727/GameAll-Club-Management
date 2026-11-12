import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../data/models/payout_method.dart';
import '../../data/models/payout_settings.dart';
import '../../data/repositories/repository_providers.dart';
import '../authentication/session_controller.dart';
import '../profile/hub/payout_widgets.dart' show showPayoutMethodSheet;
import 'payout_setup_logic.dart';
import 'payout_validation.dart';
import 'setup_ui.dart';

/// Step 5 of the setup: Payout. Bank accounts / UPI IDs, settlement settings, which earnings are included and the payout rules.
/// "Complete Setup" submits the whole setup to GameAll for approval; until it is approved the app shows only the review screen.
class PayoutSetupScreen extends ConsumerStatefulWidget {
  const PayoutSetupScreen({super.key});

  @override
  ConsumerState<PayoutSetupScreen> createState() => _PayoutSetupScreenState();
}

class _PayoutSetupScreenState extends ConsumerState<PayoutSetupScreen> {
  bool _loading = true;
  String? _loadError;
  String? _facilityId;
  String _facilityName = '';
  List<PayoutMethod> _methods = const [];
  PayoutSettings _settings = const PayoutSettings();

  bool _bankTab = true;
  final _holder = TextEditingController();
  final _number = TextEditingController();
  final _ifsc = TextEditingController();
  final _upi = TextEditingController();
  final _min = TextEditingController(text: '500');
  final _bankKey = GlobalKey<FormState>();
  final _upiKey = GlobalKey<FormState>();
  String? _bank;
  PayoutAccountType _type = PayoutAccountType.savings;
  String? _ifscNote;
  bool _ifscOk = false;
  bool _finding = false;
  bool _busy = false;
  bool _savingDraft = false;
  bool _completing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _holder.dispose();
    _number.dispose();
    _ifsc.dispose();
    _upi.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        if (mounted) context.go(AppRoutes.onboardingFacility);
        return;
      }
      final repo = ref.read(payoutRepositoryProvider);
      final methods = await repo.list(facility.id);
      final settings = await repo.loadSettings(facility.id);
      if (!mounted) return;
      setState(() {
        _facilityId = facility.id;
        _facilityName = facility.name;
        _methods = methods;
        _settings = settings;
        _min.text = '${settings.minimumPayoutInr}';
        _loading = false;
      });
    } on AppException catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _loadError = e.message;
      });
    } catch (e, stack) {
      debugPrint('Payout step load failed: $e\n$stack');
      if (mounted) setState(() {
        _loading = false;
        _loadError = 'We couldn’t load this step. Please try again.';
      });
    }
  }

  Future<void> _reload() async {
    final id = _facilityId;
    if (id == null) return;
    final methods = await ref.read(payoutRepositoryProvider).list(id);
    if (mounted) setState(() => _methods = methods);
  }

  Future<void> _run(Future<void> Function() action, String fallback) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _reload();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, stack) {
      debugPrint('Payout action failed: $e\n$stack');
      if (mounted) setState(() => _error = fallback);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findIfsc() async {
    final code = _ifsc.text.trim().toUpperCase();
    if (PayoutValidators.ifsc(code) != null) {
      setState(() {
        _ifscOk = false;
        _ifscNote = 'Enter a valid IFSC, like HDFC0001234.';
      });
      return;
    }
    setState(() {
      _finding = true;
      _ifscNote = null;
    });
    try {
      final found = await lookupIfsc(code);
      if (!mounted) return;
      setState(() {
        if (found == null) {
          _ifscOk = false;
          _ifscNote = 'We couldn’t find this IFSC. Check it and try again.';
        } else {
          _bank = found.bank;
          _ifscOk = true;
          _ifscNote = [found.bank, found.branch, found.city].where((s) => s.isNotEmpty).join(' · ');
        }
      });
    } catch (_) {
      if (mounted) setState(() {
        _ifscOk = false;
        _ifscNote = 'The IFSC directory isn’t reachable right now. You can still add the account.';
      });
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  void _onIfscChanged(String raw) {
    final inferred = bankFromIfsc(raw);
    setState(() {
      _ifscNote = null;
      if (inferred != null && _bank == null) _bank = inferred;
    });
  }

  Future<void> _addBank() async {
    final id = _facilityId;
    if (id == null || !(_bankKey.currentState?.validate() ?? false)) return;
    if (_bank == null) {
      setState(() => _error = 'Select the bank.');
      return;
    }
    await _run(() async {
      await ref.read(payoutRepositoryProvider).addBank(id, accountHolderName: _holder.text, bankName: _bank!, accountNumber: _number.text, ifsc: _ifsc.text, accountType: _type);
      _number.clear();
      _ifsc.clear();
      _bank = null;
      _ifscNote = null;
    }, 'Could not add this bank account.');
  }

  Future<void> _addUpi() async {
    final id = _facilityId;
    if (id == null || !(_upiKey.currentState?.validate() ?? false)) return;
    final holder = _holder.text.trim().isNotEmpty ? _holder.text : (ref.read(sessionControllerProvider).user?.fullName ?? _facilityName);
    await _run(() async {
      await ref.read(payoutRepositoryProvider).addUpi(id, accountHolderName: holder, upiId: _upi.text);
      _upi.clear();
    }, 'Could not add this UPI ID.');
  }

  Future<void> _edit(PayoutMethod m) async {
    final id = _facilityId;
    if (id == null) return;
    if (await showPayoutMethodSheet(context, facilityId: id, method: m, dark: false)) await _reload();
  }

  Future<void> _persist({required bool complete}) async {
    final id = _facilityId;
    if (id == null) return;
    final settings = _settings.copyWith(minimumPayoutInr: int.tryParse(_min.text.trim()) ?? -1);
    final problem = settings.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (complete && _methods.isEmpty) {
      setState(() => _error = 'Add at least one bank account or UPI ID to finish setup.');
      return;
    }
    setState(() {
      _error = null;
      _settings = settings;
      if (complete) {
        _completing = true;
      } else {
        _savingDraft = true;
      }
    });
    try {
      final payouts = ref.read(payoutRepositoryProvider);
      await payouts.saveSettings(id, settings);
      if (complete) {
        // Also flips onboarding_completed and SUBMITS the setup to GameAll for approval (migration 0200).
        await ref.read(onboardingRepositoryProvider).completeSetup(id);
        try {
          await payouts.resubmitForReview(id); // only does anything for a facility GameAll sent back
        } catch (_) {}
        // Plans are bought on the web, not in the app: a club created here simply starts its free trial.
        await ref.read(planRepositoryProvider).startFreeTrial(id);
        await ref.read(sessionControllerProvider.notifier).refresh();
        if (mounted) context.go(AppRoutes.setupReview);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draft saved. You can pick up where you left off.')));
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, stack) {
      debugPrint('Payout step save failed: $e\n$stack');
      if (mounted) setState(() => _error = 'We couldn’t finish your setup. Please try again.');
    } finally {
      if (mounted) setState(() {
        _completing = false;
        _savingDraft = false;
      });
    }
  }

  // ── pieces ─────────────────────────────────────────────────────────────

  Widget _tabs() {
    return SetupSegmented<bool>(
      label: 'Add a payout account',
      value: _bankTab,
      keyPrefix: 'payout-tab',
      options: const [(value: true, label: 'Bank Account'), (value: false, label: 'UPI')],
      onChanged: (v) => setState(() => _bankTab = v),
    );
  }

  Widget _bankForm() {
    return Form(
      key: _bankKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SetupTextField(label: 'Account Holder Name', required: true, controller: _holder, hint: 'Enter account holder name', validator: PayoutValidators.holderName, maxLength: 80),
          const SizedBox(height: 14),
          SetupDropdown<String>(
            key: ValueKey('bank-$_bank'),
            label: 'Bank Name',
            required: true,
            value: _bank,
            hint: 'Select bank',
            items: [
              for (final b in {?_bank, ...indianBanks}) DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _bank = v),
          ),
          const SizedBox(height: 14),
          SetupTextField(
            label: 'Account Number',
            required: true,
            controller: _number,
            hint: 'Enter account number',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
            validator: PayoutValidators.accountNumber,
          ),
          const SizedBox(height: 14),
          const SetupLabel('IFSC Code', required: true),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _ifsc,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(11)],
                  validator: PayoutValidators.ifsc,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onChanged: _onIfscChanged,
                  style: setupText(size: 15),
                  decoration: setupDecoration(hint: 'Enter IFSC code'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const ValueKey('find-ifsc'),
                  onPressed: _finding ? null : _findIfsc,
                  icon: _finding ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search, size: 18),
                  label: Text('Find', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.primary)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: SetupColors.primary), foregroundColor: SetupColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ],
          ),
          if (_ifscNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_ifscNote!, style: setupText(size: 12, weight: FontWeight.w500, color: _ifscOk ? SetupColors.success : const Color(0xFFB26A00), height: 1.35)),
            ),
          const SizedBox(height: 14),
          SetupSegmented<PayoutAccountType>(
            label: 'Account Type',
            required: true,
            value: _type,
            keyPrefix: 'payout-type',
            options: const [(value: PayoutAccountType.savings, label: 'Savings'), (value: PayoutAccountType.current, label: 'Current')],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: SetupButton(label: 'Add Bank Account', icon: Icons.add, onPressed: _busy ? null : _addBank)),
        ],
      ),
    );
  }

  Widget _upiForm() {
    return Form(
      key: _upiKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SetupTextField(label: 'UPI ID', required: true, controller: _upi, hint: 'Enter UPI ID (e.g., name@okaxis)', keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.done, validator: PayoutValidators.upiId),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: SetupButton(label: 'Add UPI', icon: Icons.add, onPressed: _busy ? null : _addUpi)),
        ],
      ),
    );
  }

  Widget _accountsList() {
    if (_methods.isEmpty) {
      return Text('No payout account added yet. Add a bank account or UPI ID above.', style: setupText(size: 13, color: SetupColors.secondary, height: 1.4));
    }
    return Column(
      children: [
        for (final m in _methods)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: m.isPrimary ? SetupColors.primary : SetupColors.border), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(m.type == PayoutMethodType.bank ? Icons.account_balance_outlined : Icons.smartphone_outlined, size: 20, color: SetupColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.type == PayoutMethodType.bank ? (m.bankName ?? 'Bank Account') : 'UPI', style: setupText(size: 15, weight: FontWeight.w600)),
                          Text(
                            m.type == PayoutMethodType.bank
                                ? '${m.accountType == PayoutAccountType.current ? 'Current' : 'Savings'} · A/c No. ${PayoutValidators.maskAccountNumber(m.accountLast4)}'
                                : PayoutValidators.maskUpi(m.upiId),
                            style: setupText(size: 13, color: SetupColors.secondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(tooltip: 'Edit', onPressed: _busy ? null : () => _edit(m), icon: const Icon(Icons.edit_outlined, size: 20, color: SetupColors.primary)),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: _busy ? null : () => _run(() => ref.read(payoutRepositoryProvider).delete(m.id), 'Could not remove this payout account.'),
                      icon: const Icon(Icons.delete_outline, size: 20, color: SetupColors.error),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _StatusChip(m.verification),
                    const Spacer(),
                    InkWell(
                      onTap: _busy || m.isPrimary ? null : () => _run(() => ref.read(payoutRepositoryProvider).setPrimary(m.id), 'Could not change the primary account.'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(m.isPrimary ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: m.isPrimary ? SetupColors.primary : SetupColors.placeholder),
                            const SizedBox(width: 6),
                            Text(m.isPrimary ? 'Primary' : 'Make primary', style: setupText(size: 13, weight: FontWeight.w500, color: SetupColors.secondary)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _switchRow(String key, String title, String desc, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Switch(
            key: ValueKey(key),
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: SetupColors.primary,
            inactiveTrackColor: const Color(0xFFC9C5D6),
            inactiveThumbColor: Colors.white,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(title, style: setupText(size: 15, weight: FontWeight.w600, height: 1.2)),
                const SizedBox(height: 2),
                Text(desc, style: setupText(size: 13, color: SetupColors.secondary, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _loadError != null) {
      return SetupPage(
        footer: _loadError == null ? const SizedBox(height: 52) : SetupButton(label: 'Try again', primary: true, onPressed: _load),
        children: [
          const SetupStepper(current: 5),
          const SizedBox(height: 18),
          if (_loadError != null) SetupErrorBanner(_loadError!) else const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    return SetupPage(
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) SetupErrorBanner(_error!),
          Row(
            children: [
              Expanded(child: SetupButton(label: 'Back', icon: Icons.arrow_back, onPressed: () => context.go(AppRoutes.onboardingPricing))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: SetupButton(label: 'Complete Setup', primary: true, icon: Icons.check, loading: _completing, loadingLabel: 'Submitting…', onPressed: (_savingDraft || _methods.isEmpty) ? null : () => _persist(complete: true))),
            ],
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            key: const ValueKey('save-draft'),
            onPressed: (_completing || _savingDraft) ? null : () => _persist(complete: false),
            icon: _savingDraft ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.description_outlined, size: 18, color: SetupColors.secondary),
            label: Text('Save as Draft', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.secondary)),
          ),
        ],
      ),
      children: [
        const SetupStepper(current: 5),
        const SizedBox(height: 18),
        Text('Payout', style: setupText(size: 28, weight: FontWeight.w700, height: 1.1)),
        const SizedBox(height: 6),
        Text('Set up how you receive your earnings from bookings, memberships, and coaching at your facility.', style: setupText(size: 14, color: SetupColors.secondary, height: 1.4)),
        const SizedBox(height: 18),
        SetupCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SetupCardHeading(title: 'Payout Account', description: 'Add and manage your bank account or UPI to receive payouts from GameAll.', icon: Icons.account_balance_wallet_outlined),
              const SizedBox(height: 14),
              _tabs(),
              const SizedBox(height: 14),
              _bankTab ? _bankForm() : _upiForm(),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, size: 14, color: SetupColors.secondary),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Only you can add or change these details. Your full account number is stored securely and is only visible to GameAll’s verification team.', style: setupText(size: 12, color: SetupColors.secondary, height: 1.4))),
                ],
              ),
              const SizedBox(height: 18),
              Text('Added Payout Accounts', style: setupText(size: 16, weight: FontWeight.w600)),
              const SizedBox(height: 10),
              _accountsList(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SetupCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SetupCardHeading(title: 'Settlement Settings', description: 'Configure how and when you receive your payouts.', icon: Icons.settings_outlined),
              const SizedBox(height: 14),
              SetupDropdown<SettlementFrequency>(
                label: 'Settlement Frequency',
                value: _settings.frequency,
                items: [for (final f in SettlementFrequency.values) DropdownMenuItem(value: f, child: Text(frequencyLabel(f)))],
                onChanged: (v) => setState(() => _settings = _settings.copyWith(frequency: v)),
              ),
              const SizedBox(height: 14),
              SetupTextField(
                label: 'Minimum Payout Amount',
                controller: _min,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                prefix: Padding(padding: const EdgeInsets.only(left: 14, right: 6), child: Text('₹', style: setupText(size: 15, color: SetupColors.secondary))),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: SetupColors.activeBg, borderRadius: BorderRadius.circular(10)),
                child: Text('Payouts are processed to your selected account based on the selected frequency. ${frequencyNote(_settings.frequency)}', style: setupText(size: 13, color: SetupColors.primary, height: 1.4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SetupCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SetupCardHeading(title: 'Payout Sources', description: 'Choose which earnings should be included in your payouts.', icon: Icons.layers_outlined),
              const SizedBox(height: 8),
              _switchRow('src-bookings', 'Booking Earnings', 'Court and slot bookings made by players.', _settings.includeBookings, (v) => setState(() => _settings = _settings.copyWith(includeBookings: v))),
              _switchRow('src-memberships', 'Membership Earnings', 'Payments for membership subscriptions (if enabled).', _settings.includeMemberships, (v) => setState(() => _settings = _settings.copyWith(includeMemberships: v))),
              _switchRow('src-coaching', 'Coaching Earnings', 'Payments for coaching sessions (if enabled).', _settings.includeCoaching, (v) => setState(() => _settings = _settings.copyWith(includeCoaching: v))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SetupCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SetupCardHeading(title: 'Payout Rules', description: 'Additional settings for your payouts.', icon: Icons.account_balance_wallet_outlined),
              const SizedBox(height: 8),
              _switchRow('rule-auto', 'Auto Payout', 'Automatically settle eligible earnings based on the settlement frequency.', _settings.autoPayout, (v) => setState(() => _settings = _settings.copyWith(autoPayout: v))),
              _switchRow('rule-hold', 'Hold Payout for Review', 'Manually review and approve payouts before settlement.', _settings.holdForReview, (v) => setState(() => _settings = _settings.copyWith(holdForReview: v))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('GameAll reviews your whole setup before your dashboard opens. You’ll be notified as soon as it’s approved.', style: setupText(size: 12, color: SetupColors.secondary, height: 1.4)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);

  final PayoutVerification status;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      PayoutVerification.verified => ('Verified', SetupColors.success, const Color(0xFFE8F5E9)),
      PayoutVerification.rejected => ('Couldn’t verify', SetupColors.error, const Color(0xFFFDECEA)),
      PayoutVerification.pending => ('Verification pending', const Color(0xFFB26A00), const Color(0xFFFFF4E0)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: setupText(size: 12, weight: FontWeight.w600, color: fg)),
    );
  }
}
