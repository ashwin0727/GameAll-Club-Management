import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/access.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/authentication/session_controller.dart';

/// The primary destinations — Today, Calendar, Coaching and Memberships — and everything else behind
/// [AppTab.more]. [AppTab.money] is no longer on the bar (Finance is a shortcut on Today), but the
/// Finance screens still say they are the current tab, so nothing on the bar is highlighted there.
enum AppTab { today, courts, money, members, coaching, more }

/// A place the bottom bar / "+" menu can open. [pages] = the person needs View on at least one of them to see it.
typedef _Dest = ({AppTab? tab, IconData icon, IconData activeIcon, String label, String route, List<String> pages});

const _reportPages = [
  accessPageReportOverview,
  accessPageReportCourtUtilization,
  accessPageReportRevenue,
  accessPageReportMemberships,
  accessPageReportGuestBookings,
];

/// Every destination in priority order. The first four the person can open fill the bar; whatever else they can open
/// goes behind the "+" button (then Profile, which is always there). The usual four — Today, Calendar, Coaching,
/// Memberships — come first, so someone with all of them sees exactly the bar they always did; a role missing one of
/// them gets the next destination in its place instead of an empty slot.
const _destinations = <_Dest>[
  (tab: AppTab.today, icon: Icons.today_outlined, activeIcon: Icons.today_rounded, label: 'Today', route: AppRoutes.dashboard, pages: [accessPageHome]),
  (tab: AppTab.courts, icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month_rounded, label: 'Calendar', route: AppRoutes.bookings, pages: [accessPageCalendar]),
  (tab: AppTab.coaching, icon: Icons.school_outlined, activeIcon: Icons.school_rounded, label: 'Coaching', route: AppRoutes.coaching, pages: [accessPageCoachingOverview]),
  (tab: AppTab.members, icon: Icons.groups_outlined, activeIcon: Icons.groups_rounded, label: 'Memberships', route: AppRoutes.memberships, pages: [accessPageMembershipDashboard]),
  (tab: null, icon: Icons.confirmation_number_outlined, activeIcon: Icons.confirmation_number_rounded, label: 'Guest Booking', route: AppRoutes.guestBookings, pages: [accessPageGuestBookings]),
  (tab: null, icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet_rounded, label: 'Finance', route: AppRoutes.finance, pages: [accessPageFinanceOverview]),
  (tab: null, icon: Icons.handyman_outlined, activeIcon: Icons.handyman_rounded, label: 'Maintenance', route: AppRoutes.maintenance, pages: [accessPageMaintenance]),
  (tab: null, icon: Icons.admin_panel_settings_outlined, activeIcon: Icons.admin_panel_settings_rounded, label: 'Staff', route: AppRoutes.usersRoles, pages: [accessPageStaff]),
  (tab: null, icon: Icons.bar_chart_rounded, activeIcon: Icons.bar_chart_rounded, label: 'Reports & Analytics', route: AppRoutes.reports, pages: _reportPages),
  (tab: null, icon: Icons.currency_rupee, activeIcon: Icons.currency_rupee, label: 'Refunds', route: AppRoutes.refunds, pages: [accessPageRefunds]),
  (tab: null, icon: Icons.groups_2_outlined, activeIcon: Icons.groups_2_rounded, label: 'Guest Players', route: AppRoutes.guests, pages: [accessPageGuestPlayers]),
  (tab: null, icon: Icons.account_balance_outlined, activeIcon: Icons.account_balance_rounded, label: 'Payment Methods', route: AppRoutes.profilePayouts, pages: [accessPageFacilitySettings]),
];

const _profileDestination = (
  tab: AppTab.more,
  icon: Icons.person_outline_rounded,
  activeIcon: Icons.person_rounded,
  label: 'Profile',
  route: AppRoutes.profile,
  pages: <String>[],
);

/// What this person gets: up to four on the bar, the rest (plus Profile) behind "+".
({List<_Dest> bar, List<_Dest> more}) _layoutFor(SessionState session) {
  final accessible = _destinations.where((d) => d.pages.any(session.canViewPage)).toList();
  return (bar: accessible.take(4).toList(), more: [...accessible.skip(4), _profileDestination]);
}

/// Floating bottom navigation — a rounded, shadowed bar that hovers above
/// the content, with a sliding green highlight that animates between tabs
/// and a prominent "+" action for the overflow menu.
class AppBottomNav extends ConsumerStatefulWidget {
  const AppBottomNav({super.key, required this.current});

  final AppTab current;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  ConsumerState<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends ConsumerState<AppBottomNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _menu = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 200),
  );
  OverlayEntry? _entry;

  @override
  void dispose() {
    _entry?.remove();
    _menu.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_entry != null) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    final session = ref.read(sessionControllerProvider);
    final destinations = [
      for (final d in _layoutFor(session).more) (icon: d.icon, label: d.label, route: d.route, pages: d.pages),
    ];
    _entry = OverlayEntry(
      builder: (_) => _SpeedDialOverlay(
        animation: _menu,
        destinations: destinations,
        onClose: _closeMenu,
        onSelect: (route) {
          _entry?.remove();
          _entry = null;
          _menu.value = 0;
          context.push(route);
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _menu.forward();
  }

  Future<void> _closeMenu() async {
    if (_entry == null) return;
    await _menu.reverse();
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final onProfile = widget.current == AppTab.more;
    final session = ref.watch(sessionControllerProvider);
    final initials = AppBottomNav._initials(session.user?.fullName ?? '');
    final photoUrl = session.facility?.logoUrl;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: tokens.surface2,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            border: Border.all(color: tokens.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 24,
                spreadRadius: -2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // Up to four destinations the person's role can open; anything beyond that is behind "+".
              for (final t in _layoutFor(session).bar)
                Expanded(
                  child: _NavItem(
                    icon: t.tab != null && t.tab == widget.current ? t.activeIcon : t.icon,
                    label: t.label,
                    selected: t.tab != null && t.tab == widget.current,
                    onTap: () {
                      if (t.tab != null && t.tab == widget.current) return;
                      // The usual four are tabs (replace); the others open on top, so Back returns to where you were.
                      if (t.tab != null) {
                        context.go(t.route);
                      } else {
                        context.push(t.route);
                      }
                    },
                  ),
                ),
              const SizedBox(width: AppSpacing.xs),
              onProfile
                  ? _ProfileButton(
                      initials: initials,
                      photoUrl: photoUrl,
                      onTap: _toggleMenu)
                  : _PlusButton(spin: _menu, onTap: _toggleMenu),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? tokens.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: tokens.primary.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: -2,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutBack,
              child: Icon(
                icon,
                size: 22,
                color: selected ? tokens.onPrimary : tokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? tokens.primary : tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the "+" while the Profile screen is open — the same
/// footprint, but the signed-in user's avatar in a selected (violet, glowing)
/// state.
class _ProfileButton extends StatelessWidget {
  const _ProfileButton(
      {required this.initials, required this.onTap, this.photoUrl});

  final String initials;
  final String? photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        width: 48,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hasPhoto ? tokens.surface2 : tokens.primary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          image: hasPhoto
              ? DecorationImage(
                  image: NetworkImage(photoUrl!), fit: BoxFit.cover)
              : null,
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
          boxShadow: [
            BoxShadow(
              color: tokens.primary.withValues(alpha: 0.5),
              blurRadius: 18,
              spreadRadius: -1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: hasPhoto
            ? null
            : Text(
                initials,
                style: TextStyle(
                    color: tokens.onPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
      ),
    );
  }
}

class _PlusButton extends StatelessWidget {
  const _PlusButton({required this.onTap, required this.spin});

  final VoidCallback onTap;
  final Animation<double> spin;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        width: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.primary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: tokens.primary.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: RotationTransition(
          turns: Tween<double>(begin: 0, end: 0.125).animate(
              CurvedAnimation(parent: spin, curve: Curves.easeOutCubic)),
          child: Icon(Icons.add_rounded, color: tokens.onPrimary, size: 26),
        ),
      ),
    );
  }
}

/// The full-screen speed-dial overlay opened by the "+" button — a blurred
/// scrim plus a vertical stack of destinations that scale/fade up from the
/// button, staggered. Reverses (and everything retracts) on close.
class _SpeedDialOverlay extends StatelessWidget {
  const _SpeedDialOverlay({
    required this.animation,
    required this.destinations,
    required this.onClose,
    required this.onSelect,
  });

  final Animation<double> animation;
  final List<({IconData icon, String label, String route, List<String> pages})> destinations;
  final VoidCallback onClose;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final buttonBottom = safeBottom + AppSpacing.md + (68 - 48) / 2;
    final count = destinations.length;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value;
        return Material(
          type: MaterialType.transparency,
          child: Stack(
          children: [
            // ── blurred, dimmed backdrop ──────────────────────────────
            Positioned.fill(
              child: GestureDetector(
                onTap: onClose,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                      sigmaX: 6 * v, sigmaY: 6 * v),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55 * v),
                  ),
                ),
              ),
            ),

            // ── the destinations, stacked above the button ────────────
            Positioned(
              right: 20,
              bottom: buttonBottom + 48 + 14,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height - (buttonBottom + 48 + 14) - MediaQuery.of(context).padding.top - 16,
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < count; i++)
                        _dialItem(context, tokens, i, count, v),
                    ],
                  ),
                ),
              ),
            ),

            // ── the rotating "+" → "×", bright above the scrim ────────
            Positioned(
              right: 20,
              bottom: buttonBottom,
              child: GestureDetector(
                onTap: onClose,
                child: Container(
                  height: 48,
                  width: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.primary,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.primary.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: -1,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Transform.rotate(
                    angle: v * 0.785398, // 45°
                    child: Icon(Icons.add_rounded,
                        color: tokens.onPrimary, size: 26),
                  ),
                ),
              ),
            ),
          ],
        ),
        );
      },
    );
  }

  Widget _dialItem(BuildContext context, AppColorTokens tokens, int i,
      int count, double v) {
    final d = destinations[i];
    // Bottom-most item (closest to the button) animates in first.
    final start = (count - 1 - i) * 0.12;
    final raw = ((v - start) / (1 - start)).clamp(0.0, 1.0);
    final t = Curves.easeOutBack.transform(raw).clamp(0.0, 1.2);
    return Opacity(
      opacity: raw,
      child: Transform.translate(
        offset: Offset(0, (1 - raw) * 18),
        child: Transform.scale(
          scale: 0.7 + 0.3 * t,
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: GestureDetector(
              onTap: () => onSelect(d.route),
              // Name floating on the backdrop, icon in its own glowing green
              // box — same treatment as the main "+" button — so every
              // item's icon box lands at the same fixed position along the
              // screen's right edge, with the label growing leftward from
              // it. No horizontal padding here — any inset would shift the
              // box left of the "+" button's own right:20 position instead
              // of stacking directly above it. Tapping the label or the
              // icon both trigger [onSelect].
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(d.label,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            color: Colors.white,
                            decoration: TextDecoration.none)),
                    const SizedBox(width: 12),
                    // Exactly the "+" button's box: same size, radius,
                    // shadow and icon size — not a scaled-down copy.
                    Container(
                      height: 48,
                      width: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tokens.primary,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: [
                          BoxShadow(
                            color: tokens.primary.withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: -1,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(d.icon, size: 26, color: tokens.onPrimary),
                    ),
                  ],
                ),
            ),
          ),
        ),
      ),
    );
  }
}
