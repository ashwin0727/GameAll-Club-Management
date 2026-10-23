import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../data/models/facility.dart';
import '../../data/models/playing_area.dart';
import '../../data/models/sport.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/skeleton.dart';
import '../authentication/session_controller.dart';
import '../../core/access/access.dart';

/// Profile & settings — the owner's home for everything that isn't day-to-day
/// operations: their identity, the facility's configuration, business setup,
/// app preferences and support. Backed by the real signed-in session; rows
/// without a destination yet flag "coming soon" rather than showing fake data.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int? _courts;
  int? _sports;
  int? _pricingRules;
  bool _notifications = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    try {
      final areas = await ref
          .read(playingAreaRepositoryProvider)
          .getPlayingAreas(facility.id);
      final sports = await ref
          .read(sportsRepositoryProvider)
          .getFacilitySports(facility.id);
      final plan =
          await ref.read(pricingRepositoryProvider).getPricingPlan(facility.id);
      if (!mounted) return;
      setState(() {
        _courts = areas.where((PlayingArea a) => !a.archived).length;
        _sports = sports.where((FacilitySport s) => s.enabled).length;
        _pricingRules = plan?.rules.length ?? 0;
      });
    } on AppException catch (_) {
      // Counts are decorative — the screen renders fine without them.
    }
  }

  void _soon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Coming Soon')));
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text("You'll need to sign in again to access your facility."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: context.tokens.destructive),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(sessionControllerProvider.notifier).signOut();
    }
  }

  static String _modeLabel(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final themeLabel = _modeLabel(ref.watch(themeModeControllerProvider));
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final facility = session.facility;
    final paymentsLive = facility != null &&
        (facility.onboardingStep == OnboardingStep.completed);

    return Scaffold(
      backgroundColor: t.surface0,
      appBar: AppBar(
        title: const Text('Profile',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
          children: [
            _HeaderCard(
              name: user?.fullName ?? 'Owner',
              phone: (facility?.businessPhone.isNotEmpty ?? false)
                  ? facility!.businessPhone
                  : (user?.email ?? ''),
              roleLabel: (user?.role ?? 'owner').isEmpty
                  ? 'Owner'
                  : _titleCase(user!.role),
              facilityName: facility?.name ?? 'Your facility',
              facilitySub: _facilitySub(facility),
              facilitySubLoading: _courts == null && _sports == null,
              logoUrl: facility?.logoUrl,
              onFacilityTap: () => context.push(AppRoutes.profileHub),
            ),
            const SizedBox(height: AppSpacing.xl),

            // The same sections, in the same order, as the web sidebar (src/lib/constants.ts
            // NAV_ITEMS). Mobile has no sidebar, so each web item opens its own screen from here —
            // permission-gated exactly as the web hides them, so a staff member never sees a door
            // they can't open. Members and Membership Schedule are tabs inside the Memberships hub
            // rather than separate screens, so the hub appears once, as "Dashboard".
            _Section(label: 'General', children: [
              _NavRow(
                  icon: Icons.emoji_events_outlined,
                  label: 'Tournaments',
                  pages: [accessPageTournaments],
                  onTap: () => context.push(AppRoutes.tournaments)),
            ]),


            _Section(label: 'Guest Management', children: [
              _NavRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Guest Booking',
                  pages: [accessPageGuestBookings],
                  onTap: () => context.push(AppRoutes.guestBookings)),
              _NavRow(
                  icon: Icons.groups_2_outlined,
                  label: 'Guest Players',
                  pages: [accessPageGuestPlayers],
                  onTap: () => context.push(AppRoutes.guests)),
            ]),


            _Section(label: 'Memberships Management', children: [
              _NavRow(
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  pages: [accessPageMembershipDashboard],
                  onTap: () => context.push(AppRoutes.memberships)),
              _NavRow(
                  icon: Icons.calendar_view_week_outlined,
                  label: 'Membership Schedule',
                  pages: [accessPageMembershipSchedule],
                  onTap: () => context.push(AppRoutes.membershipSchedule)),
              _NavRow(
                  icon: Icons.style_outlined,
                  label: 'Membership Plan',
                  pages: [accessPageMembershipPlans],
                  // The Plans tab of the Memberships hub (web: /memberships/v1/plans).
                  onTap: () => context.push('${AppRoutes.memberships}?tab=plans')),
              _NavRow(
                  icon: Icons.event_repeat_outlined,
                  label: 'Membership Sessions',
                  pages: [accessPageMembershipSessions],
                  onTap: () => context.push(AppRoutes.membershipSessions)),
            ]),


            ...[
              _Section(label: 'Coaching Management', children: [
                _NavRow(
                    icon: Icons.school_outlined,
                    label: 'Coaching',
                  pages: [accessPageCoachingOverview],
                    onTap: () => context.push(AppRoutes.coaching)),
                _NavRow(
                    icon: Icons.menu_book_outlined,
                    label: 'Program',
                  pages: [accessPageCoachingPrograms],
                    onTap: () => context.push(AppRoutes.coachingPrograms)),
                _NavRow(
                    icon: Icons.groups_outlined,
                    label: 'Students',
                  pages: [accessPageCoachingStudents],
                    onTap: () => context.push(AppRoutes.coachingStudents)),
                _NavRow(
                    icon: Icons.bar_chart_rounded,
                    label: 'Report',
                  pages: [accessPageCoachingReports],
                    onTap: () => context.push(AppRoutes.coachingReports)),
              ]),


            ],
            _Section(label: 'Maintenance Management', children: [
              _NavRow(
                  icon: Icons.handyman_outlined,
                  label: 'Maintenance',
                  pages: [accessPageMaintenance],
                  onTap: () => context.push(AppRoutes.maintenance)),
              _NavRow(
                  icon: Icons.assignment_outlined,
                  label: 'Maintenance Tracker',
                  pages: [accessPageMaintenance],
                  onTap: () => context.push(AppRoutes.maintenanceTickets)),
              _NavRow(
                  icon: Icons.category_outlined,
                  label: 'Issue Category',
                  pages: [accessPageMaintenanceCategories],
                  onTap: () => context.push(AppRoutes.maintenanceIssueCategories)),
            ]),


            ...[
              _Section(label: 'Staff Management', children: [
                _NavRow(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Staff',
                  pages: [accessPageStaff],
                    onTap: () => context.push(AppRoutes.usersRoles)),
                _NavRow(
                    icon: Icons.vpn_key_outlined,
                    label: 'Roles & Permission',
                  pages: [accessPageRoles],
                    onTap: () => context.push(AppRoutes.roles)),
                _NavRow(
                    icon: Icons.history_rounded,
                    label: 'Access History',
                  pages: [accessPageAccessHistory],
                    onTap: () => context.push(AppRoutes.accessHistory)),
              ]),


            ],
            if (AppConfig.inventoryEnabled && session.can('INVENTORY_VIEW')) ...[
              _Section(label: 'Inventory Management', children: [
                _NavRow(
                    icon: Icons.inventory_2_outlined,
                    label: 'Inventory Tracker',
                    onTap: () => context.push(AppRoutes.inventory)),
                _NavRow(
                    icon: Icons.widgets_outlined,
                    label: 'Items',
                    onTap: () => context.push(AppRoutes.inventoryItems)),
                _NavRow(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Stock Movement',
                    onTap: () => context.push(AppRoutes.inventoryMovements)),
                _NavRow(
                    icon: Icons.shopping_cart_outlined,
                    label: 'Purchase Orders',
                    onTap: () => context.push(AppRoutes.inventoryPurchaseOrders)),
                _NavRow(
                    icon: Icons.store_outlined,
                    label: 'Vendors',
                    onTap: () => context.push(AppRoutes.inventoryVendors)),
                _NavRow(
                    icon: Icons.label_outline_rounded,
                    label: 'Categories',
                    onTap: () => context.push(AppRoutes.inventoryCategories)),
              ]),


            ],
            _Section(label: 'Finance', children: [
              _NavRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Payments',
                  pages: [accessPageFinanceOverview],
                  onTap: () => context.push(AppRoutes.finance)),
              _NavRow(
                  icon: Icons.bar_chart_rounded,
                  label: 'Reports & Analytics',
                  pages: [accessPageReportOverview, accessPageReportCourtUtilization, accessPageReportRevenue, accessPageReportMemberships, accessPageReportGuestBookings],
                  onTap: () => context.push(AppRoutes.reports)),
              _NavRow(
                  icon: Icons.currency_exchange_rounded,
                  label: 'Refunds',
                  pages: [accessPageRefunds],
                  onTap: () => context.push(AppRoutes.refunds)),
            ]),


            _Section(label: 'Facility', children: [
              _NavRow(
                  icon: Icons.storefront_outlined,
                  label: 'Facility Details',
                  pages: [accessPageFacilitySettings],
                  onTap: () => context.push(AppRoutes.profileFacilityInfo)),
              _NavRow(
                  icon: Icons.sports_tennis_outlined,
                  label: 'Sports & Courts',
                  pages: [accessPageFacilitySettings],
                  trailing: _courts == null ? null : '$_courts',
                  trailingLoading: _courts == null,
                  onTap: () => context.push(AppRoutes.profileSportsCourts)),
              _NavRow(
                  icon: Icons.schedule_outlined,
                  label: 'Operating Hours',
                  pages: [accessPageFacilitySettings],
                  onTap: () => context.push(AppRoutes.profileHours)),
              _NavRow(
                  icon: Icons.tune_rounded,
                  label: 'Pricing Rules',
                  pages: [accessPageFacilitySettings],
                  trailing:
                      _pricingRules == null ? null : '$_pricingRules active',
                  trailingLoading: _pricingRules == null,
                  onTap: () => context.push(AppRoutes.profilePricing)),
              _NavRow(
                  icon: Icons.link_rounded,
                  label: 'Public Booking & Join Links',
                  pages: [accessPageFacilitySettings],
                  onTap: () => _joinLinkSheet(facility)),
            ]),


            _Section(label: 'Business', children: [
              _NavRow(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Payments & Payouts',
                  pages: [accessPageFacilitySettings],
                trailing: paymentsLive ? 'Live' : 'Set up',
                trailingTone: paymentsLive ? t.primary : t.warning,
                trailingDot: paymentsLive,
                onTap: () => context.push(AppRoutes.profilePayouts),
              ),
              _NavRow(
                  icon: Icons.receipt_long_outlined,
                  label: 'Invoices & Tax',
                  onTap: _soon),
              // Labelled for where it actually lands — there is no
              // expense-categories screen; this is the Expenses list.
              _NavRow(
                  icon: Icons.receipt_outlined,
                  label: 'Expenses',
                  pages: [accessPageFinanceExpenses],
                  onTap: () => context.push(AppRoutes.financeExpenses)),
              _NavRow(
                  icon: Icons.pending_actions_outlined,
                  label: 'Pending Payments',
                  pages: [accessPageFinancePayments],
                  onTap: () =>
                      context.push(AppRoutes.financePendingPayments)),
              _NavRow(
                  icon: Icons.point_of_sale_outlined,
                  label: 'Daily Closing',
                  pages: [accessPageFinanceDailyClosing],
                  onTap: () => context.push(AppRoutes.financeDailyClosing)),
              _NavRow(
                  icon: Icons.trending_up_rounded,
                  label: 'Profit & Loss',
                  pages: [accessPageFinancePnl],
                  onTap: () => context.push(AppRoutes.financeProfitLoss)),
            ]),


            _Section(label: 'App', children: [
              _ToggleRow(
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                value: _notifications,
                onChanged: (v) => setState(() => _notifications = v),
              ),
              _NavRow(
                  icon: Icons.contrast_rounded,
                  label: 'Appearance',
                  trailing: themeLabel,
                  onTap: _appearanceSheet),
              _NavRow(
                  icon: Icons.language_rounded,
                  label: 'Language',
                  trailing: 'English',
                  onTap: _soon),
            ]),


            _Section(label: 'Support', children: [
              _NavRow(
                  icon: Icons.help_outline_rounded,
                  label: 'Help Centre',
                  onTap: _soon),
              _NavRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Contact Us',
                  onTap: _contact),
              _NavRow(
                  icon: Icons.star_outline_rounded,
                  label: "What's new",
                  onTap: _soon),
            ]),


            _SignOutButton(onTap: _confirmSignOut),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.more),
    );
  }

  String _facilitySub(Facility? f) {
    if (f == null) return '';
    final bits = <String>[];
    if (_courts != null) bits.add('$_courts court${_courts == 1 ? '' : 's'}');
    if (_sports != null) bits.add('$_sports sport${_sports == 1 ? '' : 's'}');
    if (f.address.city.isNotEmpty) bits.add(f.address.city);
    return bits.join('  ·  ');
  }

  Future<void> _appearanceSheet() async {
    final t = context.tokens;
    final current = ref.read(themeModeControllerProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Appearance',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.md),
              for (final m in const [
                (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
                (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
              ])
                InkWell(
                  onTap: () {
                    ref
                        .read(themeModeControllerProvider.notifier)
                        .setMode(m.$1);
                    Navigator.pop(sheet);
                  },
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(m.$3,
                            size: 20,
                            color: current == m.$1
                                ? t.primary
                                : t.textSecondary),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                            child: Text(m.$2,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                        if (current == m.$1)
                          Icon(Icons.check_rounded,
                              size: 20, color: t.primary),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _joinLinkSheet(Facility? f) async {
    // `/join/[facilityId]` (web) is keyed by the facility's UUID id — its
    // backing RPC (`get_public_membership_signup_info`) takes a `uuid`
    // param and can't resolve the human-readable slug.
    final id = f?.id;
    final link = id == null || id.isEmpty
        ? 'https://club.gameall.co'
        : 'https://club.gameall.co/join/$id';
    final t = context.tokens;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Public Booking & Join Link',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Share this so players can book or join your facility.',
                  style:
                      TextStyle(fontSize: 12, color: t.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: t.borderColor),
                ),
                child: SelectableText(link,
                    style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: link));
                        Navigator.pop(sheet);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link Copied')));
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheet);
                        launchUrl(Uri.parse(link),
                            mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Open'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _contact() async {
    final ok = await launchUrl(
        Uri.parse('mailto:support@gameall.in?subject=GameAll%20support'));
    if (!ok && mounted) _soon();
  }

  static String _titleCase(String v) =>
      v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);
}

// ─────────────────────────────────────────────────────── header card ──

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.name,
    required this.phone,
    required this.roleLabel,
    required this.facilityName,
    required this.facilitySub,
    this.facilitySubLoading = false,
    required this.logoUrl,
    required this.onFacilityTap,
  });

  final String name;
  final String phone;
  final String roleLabel;
  final String facilityName;
  final String facilitySub;

  /// True while the court/sport counts behind [facilitySub] are still
  /// fetching — shows a short skeleton line instead of hiding the row.
  final bool facilitySubLoading;
  final String? logoUrl;
  final VoidCallback onFacilityTap;

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onC = t.onAccent(t.primary);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: t.accentSolid(t.primary),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.violet,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  image: (logoUrl != null && logoUrl!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(logoUrl!), fit: BoxFit.cover)
                      : null,
                ),
                child: (logoUrl != null && logoUrl!.isNotEmpty)
                    ? null
                    : Text(_initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: onC)),
                    const SizedBox(height: 2),
                    Text(phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: onC.withValues(alpha: 0.75))),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: onC.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(roleLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: onC)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Material(
            color: t.surface1,
            borderRadius: BorderRadius.circular(AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onFacilityTap,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: t.borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(Icons.home_work_outlined,
                          size: 18, color: t.primary),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(facilityName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800)),
                          if (facilitySubLoading) ...[
                            const SizedBox(height: 3),
                            const AppSkeleton(width: 60, height: 11),
                          ] else if (facilitySub.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(facilitySub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: t.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 20, color: t.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────── rows ──

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(
            height: 1,
            thickness: 1,
            indent: 52,
            color: t.borderColor.withValues(alpha: 0.6)));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.trailingTone,
    this.trailingDot = false,
    this.trailingLoading = false,
    this.pages = const [],
  });

  /// The row is hidden unless the person can view at least one of these pages (empty = always shown).
  final List<String> pages;

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;
  final Color? trailingTone;
  final bool trailingDot;

  /// True while the count backing [trailing] hasn't resolved yet — shows a
  /// short skeleton line instead of leaving the subtitle blank for that
  /// first fetch cycle.
  final bool trailingLoading;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: t.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (trailingLoading) ...[
              const AppSkeleton(width: 60, height: 11),
              const SizedBox(width: 4),
            ] else if (trailing != null) ...[
              if (trailingDot) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: trailingTone ?? t.primary,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
              ],
              Text(trailing!,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: trailingTone ?? t.textSecondary)),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded,
                size: 20, color: t.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: t.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: t.primary,
          ),
        ],
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.destructive.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: t.destructive.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout_rounded, size: 18, color: t.destructive),
              const SizedBox(width: AppSpacing.sm),
              Text('Sign Out',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: t.destructive)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One titled group of menu rows. Rows whose page the person's role doesn't include are dropped, and a group left with
/// no rows disappears entirely (title and spacing too).
class _Section extends ConsumerWidget {
  const _Section({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final visible = children.where((c) {
      if (c is _NavRow && c.pages.isNotEmpty) return c.pages.any(session.canViewPage);
      return true;
    }).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.textSecondary)),
          ),
          _GroupCard(children: visible),
        ],
      ),
    );
  }
}
