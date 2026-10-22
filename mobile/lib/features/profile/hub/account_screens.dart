import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/profile_hub.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../authentication/auth_widgets.dart';
import '../../authentication/session_controller.dart';
import 'facility_sections.dart';
import 'hub_providers.dart';
import 'hub_widgets.dart';

// ── Personal information ───────────────────────────────────────────────────

/// Your account details, then the facility they belong to.
class PersonalInfoScreen extends ConsumerWidget {
  const PersonalInfoScreen({super.key});

  String _formatPhone(String phone) {
    final n = phone.replaceAll(RegExp(r'[\s-]'), '').replaceFirst(RegExp(r'^\+?91(?=\d{10}$)'), '');
    return RegExp(r'^\d{10}$').hasMatch(n) ? '+91 ${n.substring(0, 5)} ${n.substring(5)}' : phone;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(hubProfileProvider);
    final facility = ref.watch(sessionControllerProvider).facility;
    return HubPage(
      title: 'Personal Information',
      onRefresh: () async {
        ref.invalidate(hubProfileProvider);
        await ref.read(hubProfileProvider.future);
      },
      children: [
        HubAsync<HubProfile>(
          value: profile,
          onRetry: () => ref.invalidate(hubProfileProvider),
          builder: (p) {
            // Until a personal number is added, the facility's own contact number stands in for it.
            final mobile = (p.phone?.trim().isNotEmpty ?? false) ? p.phone! : (facility?.businessPhone ?? '');
            return HubCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HubInfoRow('Full name', p.fullName),
                  HubInfoRow('Role', p.roleTitle),
                  HubInfoRow('Mobile number', mobile.isEmpty ? null : _formatPhone(mobile)),
                  HubInfoRow('Email address', p.email),
                  HubInfoRow('Member since', hubDate(p.createdAt)),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        if (facility != null) FacilityInfoCard(facility: facility),
      ],
    );
  }
}

// ── Help & support ─────────────────────────────────────────────────────────

const _faqs = <(String, String)>[
  (
    'How do I add a booking for a walk-in guest?',
    'Open Guest Bookings and choose Create Booking. Pick the guest, the sport and court, the time, then record the payment. The slot is held the moment you confirm it.',
  ),
  (
    'How do I create a membership for a member?',
    'Go to Memberships and choose Create Membership. Select the member, a plan and the court timings they will use, then record what they have paid. Anything unpaid shows up under Pending Payments.',
  ),
  (
    "Where can I see what I'm owed?",
    'Finance → Pending Payments lists every membership and guest booking that still has a balance, with the due date. Collect a payment from there and it updates your Finance and Reports figures straight away.',
  ),
  (
    'How do I change my courts, timings or pricing?',
    'Open Profile → Facility and use the Edit button beside the section you want to change. Existing bookings keep the price they were made at.',
  ),
  (
    'Where do my payouts go?',
    'To the primary bank account or UPI ID under Payments & Payouts. Only the facility owner can see or change these details.',
  ),
  (
    'What does my GameAll plan cost, and when does it end?',
    'GameAll charges a flat membership fee, never a commission on your bookings. Your plan, its price and its valid-till date are shown on your Profile page.',
  ),
  (
    'I forgot my password.',
    'Use Settings → Change password while you are signed in. If you are signed out, choose “Forgot password” on the sign-in screen and we will email you a reset link.',
  ),
];

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _category = 'GENERAL';
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _sent = false;
      _error = null;
    });
    try {
      await ref.read(profileHubRepositoryProvider).createTicket(
            facility.id,
            category: _category,
            subject: _subject.text,
            message: _message.text,
          );
      _subject.clear();
      _message.clear();
      ref.invalidate(supportTicketsProvider);
      if (mounted) setState(() => _sent = true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send your request. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tickets = ref.watch(supportTicketsProvider);
    return HubPage(
      title: 'Help & Support',
      onRefresh: () async {
        ref.invalidate(supportTicketsProvider);
        await ref.read(supportTicketsProvider.future);
      },
      children: [
        Text("Find an answer, or tell us what's wrong and we'll sort it out.", style: TextStyle(fontSize: 13, color: t.textSecondary)),
        const SizedBox(height: AppSpacing.lg),
        HubCard(
          title: 'Frequently asked questions',
          subtitle: 'Quick answers to what owners ask most.',
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
          child: Column(
            children: [
              for (final (q, a) in _faqs)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    title: Text(q, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary)),
                    children: [Text(a, style: TextStyle(fontSize: 13, color: t.textSecondary, height: 1.45))],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        HubCard(
          title: 'Raise a support request',
          subtitle: 'Our team replies by email.',
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppDropdown<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'What is it about?'),
                  items: [for (final e in supportCategories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _category = v ?? 'GENERAL'),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Subject',
                  controller: _subject,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Add a short subject (at least 3 characters).' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Tell us what happened',
                  controller: _message,
                  maxLines: 5,
                  validator: (v) => (v?.trim().length ?? 0) < 10 ? 'Tell us a little more (at least 10 characters).' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!, style: TextStyle(color: t.destructive, fontSize: 13)),
                ],
                if (_sent) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text("Thanks — your request is with our team. We'll get back to you by email.",
                      style: TextStyle(color: t.success, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: AppSpacing.lg),
                AuthGradientButton(label: 'Send request', loadingLabel: 'Sending…', isLoading: _sending, onPressed: _send),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        HubCard(
          title: 'Your recent requests',
          child: tickets.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Text('Unable to load your requests.', style: TextStyle(color: t.destructive)),
            data: (list) => list.isEmpty
                ? Text("You haven't raised any requests yet.", style: TextStyle(color: t.textSecondary))
                : Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) Divider(height: AppSpacing.lg, color: t.borderColor),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(list[i].subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: t.textPrimary)),
                                  Text('${supportCategories[list[i].category] ?? list[i].category} · ${hubDate(list[i].createdAt)}',
                                      style: TextStyle(fontSize: 12, color: t.textSecondary)),
                                ],
                              ),
                            ),
                            _TicketStatus(status: list[i].status),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _TicketStatus extends StatelessWidget {
  const _TicketStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final open = status == 'OPEN' || status == 'IN_PROGRESS';
    final c = open ? t.success : t.textSecondary;
    final label = switch (status) {
      'IN_PROGRESS' => 'In progress',
      'RESOLVED' => 'Resolved',
      'CLOSED' => 'Closed',
      _ => 'Open',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

// ── Settings ───────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  NotificationPrefs? _prefs;
  bool _changing = false;
  bool _changed = false;
  String? _prefsError;
  String? _passwordError;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _toggle(NotificationPrefs current, NotificationPrefs next) async {
    setState(() {
      _prefs = next;
      _prefsError = null;
    });
    try {
      await ref.read(profileHubRepositoryProvider).saveNotificationPrefs(next);
      ref.invalidate(notificationPrefsProvider);
    } catch (_) {
      if (mounted) {
        setState(() {
          _prefs = current;
          _prefsError = 'Could not save your settings.';
        });
      }
    }
  }

  Future<void> _changePassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _changing = true;
      _changed = false;
      _passwordError = null;
    });
    try {
      await ref.read(profileHubRepositoryProvider).changePassword(_password.text);
      _password.clear();
      _confirm.clear();
      if (mounted) setState(() => _changed = true);
    } on AppException catch (e) {
      if (mounted) setState(() => _passwordError = e.message);
    } catch (_) {
      if (mounted) setState(() => _passwordError = 'Could not change your password.');
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final loaded = ref.watch(notificationPrefsProvider);
    final prefs = _prefs ?? loaded.asData?.value ?? const NotificationPrefs();
    Widget row(String title, String sub, bool value, NotificationPrefs Function(bool) next) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: t.textPrimary)),
          subtitle: Text(sub, style: TextStyle(fontSize: 12, color: t.textSecondary)),
          value: value,
          onChanged: loaded.isLoading ? null : (v) => _toggle(prefs, next(v)),
        );

    return HubPage(
      title: 'Settings',
      children: [
        HubCard(
          title: 'Notifications',
          subtitle: 'Choose what you want to hear about. Changes save as you make them.',
          child: Column(
            children: [
              row('Bookings', 'New, changed and cancelled bookings.', prefs.bookings, (v) => prefs.copyWith(bookings: v)),
              row('Payments', 'Payments received, refunds and anything still pending.', prefs.payments, (v) => prefs.copyWith(payments: v)),
              row('Memberships', 'New memberships, renewals and ones about to end.', prefs.memberships, (v) => prefs.copyWith(memberships: v)),
              row('Weekly summary', 'A weekly recap of bookings and revenue.', prefs.reports, (v) => prefs.copyWith(reports: v)),
              if (_prefsError != null) Text(_prefsError!, style: TextStyle(color: t.destructive, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        HubCard(
          title: 'Change password',
          subtitle: "Use a password you don't use anywhere else.",
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'New password',
                  controller: _password,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v?.length ?? 0) < 8 ? 'Password must be at least 8 characters.' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Confirm new password',
                  controller: _confirm,
                  obscureText: true,
                  validator: (v) => v != _password.text ? 'Passwords do not match.' : null,
                ),
                if (_passwordError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_passwordError!, style: TextStyle(color: t.destructive, fontSize: 13)),
                ],
                if (_changed) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Your password has been changed.', style: TextStyle(color: t.success, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: AppSpacing.lg),
                AuthGradientButton(label: 'Update password', loadingLabel: 'Updating…', isLoading: _changing, onPressed: _changePassword),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
