import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/gameall_buttons.dart';
import '../../core/widgets/hover_scope.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/reveal.dart';
import '../auth/application/auth_providers.dart';
import '../auth/presentation/login_flow.dart';
import '../player_home/application/player_home_controller.dart';
import '../player_home/presentation/pages/player_home_page.dart';
import '../player_home/presentation/widgets/desktop_backdrop.dart';
import '../player_home/presentation/widgets/player_bottom_nav.dart';
import '../player_home/presentation/widgets/player_header.dart';
import '../player_home/presentation/widgets/player_search_bar.dart';
import '../venues/presentation/discover_venues_page.dart';
import '../venues/presentation/coaching_enroll_page.dart';
import '../venues/presentation/enroll_membership_page.dart';
import '../venues/presentation/guest_booking_page.dart';
import '../venues/presentation/venue_detail_page.dart';
import 'coming_soon_page.dart';
import 'player_pages.dart';

/// The signed-in frame of the Player app: the five tabs, with the bottom navigation on a phone and a top navigation bar on a
/// wide window. Each tab keeps its own state (scroll position, selections) while another tab is open.
class PlayerShell extends ConsumerStatefulWidget {
  const PlayerShell({
    super.key,
    this.initialTab = PlayerTab.home,
    this.initialRoute,
    this.onNavigate,
  });

  final PlayerTab initialTab;

  /// A route to open straight away: on the web, the address the browser was refreshed on (`/venue/<id>`, `/explore` ...).
  final String? initialRoute;

  /// Replaces opening a route (tests use it to record taps).
  final RouteCallback? onNavigate;

  @override
  ConsumerState<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends ConsumerState<PlayerShell> {
  late PlayerTab _tab = widget.initialTab;

  /// A brand-bar page (Guest Booking, Memberships, Coaching, Tournaments) shown inside the shell on a wide window, like Venues.
  String? _page;

  /// The venue whose page is open inside the shell on a wide window (a phone pushes the page instead).
  String? _venueId;

  /// The venue whose Book a Court page is open inside the shell on a wide window.
  String? _bookingId;

  /// The venue whose Enroll Membership page is open inside the shell on a wide window.
  String? _enrollId;

  /// The venue whose Coaching enrolment page is open inside the shell on a wide window.
  String? _coachingId;

  /// The address last written to the browser's address bar.
  late String _reportedRoute = widget.initialRoute ?? AppRoutes.home;

  @override
  void initState() {
    super.initState();
    final first = widget.initialRoute;
    if (first != null && first != AppRoutes.home) {
      // after the first frame, so a phone can push the page onto the navigator
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _go(first);
      });
    }
  }

  /// The address of what the shell shows now. The wide shell switches pages without the navigator, so it keeps the address bar in
  /// step itself: a refresh then comes back to the same page instead of Home.
  String _currentRoute() {
    if (_coachingId != null) return AppRoutes.coachingEnrollPath(_coachingId!);
    if (_enrollId != null) return AppRoutes.enrollPath(_enrollId!);
    if (_bookingId != null) return AppRoutes.bookPath(_bookingId!);
    if (_venueId != null) return AppRoutes.venuePath(_venueId!);
    if (_page != null) return _page!;
    return switch (_tab) {
      PlayerTab.bookings => AppRoutes.bookings,
      PlayerTab.explore => AppRoutes.explore,
      PlayerTab.profile => AppRoutes.profile,
      _ => AppRoutes.home,
    };
  }

  void _syncAddressBar() {
    if (!kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.onNavigate != null) return;
      // a page pushed on top of the shell (phone) owns the address while it is open
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final route = _currentRoute();
      if (route == _reportedRoute) return;
      _reportedRoute = route;
      SystemNavigator.routeInformationUpdated(
        uri: Uri.parse(route),
        replace: true,
      );
    });
  }

  static const _inShell = {
    AppRoutes.guestBooking,
    AppRoutes.memberships,
    AppRoutes.coaching,
    AppRoutes.tournaments,
  };

  void _select(PlayerTab t) => setState(() {
    _tab = t;
    _page = null;
    _venueId = null;
    _bookingId = null;
    _enrollId = null;
    _coachingId = null;
  });

  void _go(String route) {
    final custom = widget.onNavigate;
    if (custom != null) return custom(route);
    // Login is a pop-up on a wide window and a full page on a phone, never a page in the shell.
    if (route == AppRoutes.login) {
      showPlayerLogin(context);
      return;
    }
    if (_inShell.contains(route) &&
        MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint) {
      return setState(() {
        _page = route;
        _venueId = null;
        _bookingId = null;
        _enrollId = null;
        _coachingId = null;
      });
    }
    // "/venue/<id>": a venue's own page
    final venueId = AppRoutes.venueIdOf(route);
    if (venueId != null) {
      if (MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint) {
        return setState(() {
          _venueId = venueId;
          _page = null;
          _bookingId = null;
          _enrollId = null;
          _coachingId = null;
        });
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: route),
          builder: (_) => VenueDetailPage(venueId: venueId, onNavigate: _go),
        ),
      );
      return;
    }
    // "/book/<id>": a venue's Book a Court page
    final bookingId = AppRoutes.bookVenueIdOf(route);
    if (bookingId != null) {
      if (MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint) {
        return setState(() {
          _bookingId = bookingId;
          _enrollId = null;
          _coachingId = null;
          _venueId = null;
          _page = null;
        });
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: route),
          builder: (_) => GuestBookingPage(venueId: bookingId, onNavigate: _go),
        ),
      );
      return;
    }
    // "/enroll/<id>": a venue's Enroll Membership page
    final enrollId = AppRoutes.enrollVenueIdOf(route);
    if (enrollId != null) {
      if (MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint) {
        return setState(() {
          _enrollId = enrollId;
          _coachingId = null;
          _bookingId = null;
          _venueId = null;
          _page = null;
        });
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: route),
          builder: (_) =>
              EnrollMembershipPage(venueId: enrollId, onNavigate: _go),
        ),
      );
      return;
    }
    // "/coaching-enroll/<id>": a venue's Coaching page (programmes, coaches, time slots, pay)
    final coachingId = AppRoutes.coachingEnrollVenueIdOf(route);
    if (coachingId != null) {
      if (MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint) {
        return setState(() {
          _coachingId = coachingId;
          _enrollId = null;
          _bookingId = null;
          _venueId = null;
          _page = null;
        });
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: route),
          builder: (_) =>
              CoachingEnrollPage(venueId: coachingId, onNavigate: _go),
        ),
      );
      return;
    }
    switch (route) {
      case AppRoutes.home:
        return _select(PlayerTab.home);
      case AppRoutes.bookings:
        return _select(PlayerTab.bookings);
      case AppRoutes.explore:
        return _select(PlayerTab.explore);
      case AppRoutes.profile:
        return _select(PlayerTab.profile);
      default:
        Navigator.of(context).pushNamed(route);
    }
  }

  void _quick() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final p = sheetContext.palette;
        Widget action(IconData icon, String label, String route) => HoverRegion(
          child: ListTile(
            leading: Icon(icon, color: p.highlight),
            title: HoverText(
              label,
              style: AppTextStyles.body(p.primaryText)
                  .copyWith(fontWeight: FontWeight.w500),
            ),
            minTileHeight: 52,
            onTap: () {
              Navigator.of(sheetContext).pop();
              _go(route);
            },
          ),
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              action(
                Icons.event_available_outlined,
                'Book a court',
                AppRoutes.guestBooking,
              ),
              action(
                Icons.diamond_outlined,
                'Explore memberships',
                AppRoutes.memberships,
              ),
              action(Icons.school_outlined, 'Find a coach', AppRoutes.coaching),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncAddressBar();
    final p = context.palette;
    final wide =
        MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;
    // On a wide window the brand bar is part of the page and scrolls away with it (it is not pinned). Pages that do not scroll
    // simply show it above their content.
    final bar = wide
        ? _TopBar(
            current: _tab,
            page: _page,
            onSelect: _select,
            onNavigate: _go,
          )
        : null;
    Widget withBar(Widget page, {Key? key}) => bar == null
        ? page
        : Column(
            children: [
              bar,
              Expanded(
                child: KeyedSubtree(key: key, child: page),
              ),
            ],
          );
    final pages = IndexedStack(
      index: _tab == PlayerTab.quick ? 0 : _tab.index.clamp(0, 4),
      children: [
        PlayerHomePage(onNavigate: _go, desktopHeader: bar),
        withBar(
          const ComingSoonPage(
            title: 'Bookings',
            icon: Icons.calendar_month_outlined,
            message: 'Your upcoming and past bookings will be listed here.',
            embedded: true,
          ),
        ),
        const SizedBox.shrink(),
        withBar(DiscoverVenuesPage(onNavigate: _go)),
        withBar(const _ProfileTab()),
      ],
    );

    if (wide) {
      return Scaffold(
        backgroundColor: p.background,
        body: Stack(
          children: [
            // The page background: navy-to-blue gradient, soft light and glowing arcs (no panels, no lines).
            const Positioned.fill(child: DesktopBackdrop()),
            Positioned.fill(
              child: _coachingId != null
                  ? withBar(
                      CoachingEnrollPage(
                        venueId: _coachingId!,
                        onNavigate: _go,
                        embedded: true,
                      ),
                      key: ValueKey('coaching-$_coachingId'),
                    )
                  : _enrollId != null
                  ? withBar(
                      EnrollMembershipPage(
                        venueId: _enrollId!,
                        onNavigate: _go,
                        embedded: true,
                      ),
                      key: ValueKey('enroll-$_enrollId'),
                    )
                  : _bookingId != null
                  ? withBar(
                      GuestBookingPage(
                        venueId: _bookingId!,
                        onNavigate: _go,
                        embedded: true,
                      ),
                      key: ValueKey('book-$_bookingId'),
                    )
                  : _venueId != null
                  ? withBar(
                      VenueDetailPage(
                        venueId: _venueId!,
                        onNavigate: _go,
                        embedded: true,
                      ),
                      key: ValueKey('venue-$_venueId'),
                    )
                  : _page == null
                  ? pages
                  : withBar(
                      playerPageForRoute(
                        _page!,
                        embedded: true,
                        onNavigate: _go,
                      ),
                      key: ValueKey(_page),
                    ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: p.background,
      body: pages,
      bottomNavigationBar: PlayerBottomNavigation(
        current: _tab,
        onSelect: _select,
        onQuick: _quick,
      ),
    );
  }
}

/// The brand bar lands once, when the app opens. Opening another page later must not replay it.
bool _brandBarLanded = false;

/// The wide-screen brand bar: the GameAll logo (back to Home) on the left; Venues, Memberships, Coaching, Tournaments, Login and a
/// Location button on the right. It sits directly on the page: no background panel and no line between it and the content.
class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.current,
    required this.page,
    required this.onSelect,
    required this.onNavigate,
  });

  final PlayerTab current;
  final String? page;
  final ValueChanged<PlayerTab> onSelect;
  final RouteCallback onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final animate = !_brandBarLanded;
    if (animate) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _brandBarLanded = true,
      );
    }
    // The logo settles in from above, then the links one by one, then the Location button.
    Widget land(int ms, Widget child) => animate
        ? Reveal(
            delay: Duration(milliseconds: ms),
            duration: const Duration(milliseconds: 300),
            dy: 0,
            child: child,
          )
        : child;

    Widget link(String label, {PlayerTab? tab, String? route}) {
      final selected = tab != null
          ? (tab == current && page == null)
          : route == page;
      return Pressable(
        key: ValueKey('nav-$label'),
        onTap: () => tab != null ? onSelect(tab) : onNavigate(route!),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            // the page you are on is a filled blue pill, the others are plain text
            color: selected ? AppColors.blue : Colors.transparent,
          ),
          child: HoverText(
            label,
            style:
                AppTextStyles.body(
                  selected
                      ? Colors.white
                      : p.primaryText.withValues(alpha: 0.9),
                ).copyWith(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
      );
    }

    final city = ref.watch(selectedCityProvider);
    final unread =
        ref.watch(playerHomeProvider).value?.unreadNotifications ?? 0;

    return SizedBox(
      height: 84,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppDimensions.desktopSidePadding(
            MediaQuery.sizeOf(context).width,
          ),
        ),
        child: Row(
          children: [
            land(
              0,
              Semantics(
                button: true,
                label: 'GameAll, go to Home',
                child: Pressable(
                  key: const ValueKey('brand-home'),
                  onTap: () => onSelect(PlayerTab.home),
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: GameAllLogo(height: 34),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 36),
            // No Home link: the logo is the way home.
            land(50, link('Venues', tab: PlayerTab.explore)),
            land(70, link('Memberships', route: AppRoutes.memberships)),
            land(90, link('Coaching', route: AppRoutes.coaching)),
            land(110, link('Tournaments', route: AppRoutes.tournaments)),
            const Spacer(),
            // The picked city, in an outlined pill: the Location button.
            land(
              140,
              Semantics(
                button: true,
                label: 'Location, $city',
                child: Pressable(
                  key: const ValueKey('location-button'),
                  onTap: () => showCityPicker(context, ref),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: p.isDark
                          ? AppColors.darkBackground.withValues(alpha: 0.35)
                          : p.surface,
                      border: Border.all(
                        color: AppColors.violet.withValues(
                          alpha: p.isDark ? 0.7 : 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: p.highlight,
                        ),
                        const SizedBox(width: 8),
                        HoverText(
                          city,
                          style: AppTextStyles.button(p.primaryText)
                              .copyWith(fontSize: 14),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: p.secondaryText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            land(
              160,
              NotificationBell(
                unread: unread,
                onPressed: () => onNavigate(AppRoutes.notifications),
              ),
            ),
            const SizedBox(width: 8),
            land(
              180,
              _AccountAvatar(onLogin: () => onNavigate(AppRoutes.login)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The round profile picture at the right of the brand bar. Signed out, it is a person icon that opens Login; signed in, it shows the
/// player's initials and opens a menu to log out.
class _AccountAvatar extends ConsumerWidget {
  const _AccountAvatar({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(currentPlayerProvider);
    // A player who is already signed in must not see the signed-out avatar flash while the page reloads: hold the space until we know.
    if (player == null &&
        ref.watch(authControllerProvider).isLoading &&
        ref.read(playerAuthRepositoryProvider).isSignedIn) {
      return const SizedBox(width: 44, height: 44);
    }
    final p = context.palette;
    Widget circle(Widget child) => Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.accentGradient,
      ),
      child: child,
    );
    if (player == null) {
      return Semantics(
        button: true,
        label: 'Login',
        child: Pressable(
          key: const ValueKey('login-button'),
          onTap: onLogin,
          borderRadius: BorderRadius.circular(22),
          child: circle(
            const Icon(Icons.person_rounded, size: 26, color: Colors.white),
          ),
        ),
      );
    }
    return PopupMenuButton<String>(
      key: const ValueKey('account-menu'),
      tooltip: 'Account',
      offset: const Offset(0, 52),
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.border),
      ),
      onSelected: (v) {
        if (v == 'logout') ref.read(authControllerProvider.notifier).signOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            player.phone.isEmpty ? player.fullName : '+91 ${player.phone}',
            style: AppTextStyles.support(p.secondaryText),
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 18, color: p.primaryText),
              const SizedBox(width: 10),
              Text('Log out', style: AppTextStyles.body(p.primaryText)),
            ],
          ),
        ),
      ],
      child: circle(
        Text(player.initials, style: AppTextStyles.cardHeading(Colors.white)),
      ),
    );
  }
}

/// Profile tab: who is signed in (with Log out), or a Log in button.
class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final player = ref.watch(currentPlayerProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppDimensions.cardBorderRadius,
        border: Border.all(color: p.border),
      ),
      child: player == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are not signed in',
                  style: AppTextStyles.cardHeading(p.primaryText),
                ),
                const SizedBox(height: 4),
                Text(
                  'Log in with your phone number to see your memberships, coaching and bookings from every club.',
                  style: AppTextStyles.support(p.secondaryText),
                ),
                const SizedBox(height: 14),
                GameAllButton.gradient(
                  key: const ValueKey('profile-login'),
                  label: 'Log in',
                  expand: true,
                  onPressed: onLogin,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.brandGradient,
                      ),
                      child: Text(
                        player.initials,
                        style: AppTextStyles.cardHeading(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            player.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardHeading(p.primaryText),
                          ),
                          Text(
                            '+91 ${player.phone}',
                            style: AppTextStyles.support(p.secondaryText),
                          ),
                          if (player.email != null)
                            Text(
                              player.email!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.support(p.secondaryText),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                GameAllButton.secondary(
                  key: const ValueKey('profile-logout'),
                  label: 'Log out',
                  icon: Icons.logout_rounded,
                  expand: true,
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                ),
              ],
            ),
    );
  }
}

/// Profile: appearance (Dark / Light) is all that exists so far.
class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final mode = ref.watch(themeModeProvider);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppDimensions.phoneMaxWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.all(AppDimensions.screenPadding),
            children: [
              Text('Profile', style: AppTextStyles.greeting(p.primaryText)),
              const SizedBox(height: 20),
              _AccountCard(onLogin: () => showPlayerLogin(context)),
              const SizedBox(height: 16),
              Material(
                color: p.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: AppDimensions.cardBorderRadius,
                  side: BorderSide(color: p.border),
                ),
                child: SwitchListTile(
                  key: const ValueKey('theme-switch'),
                  value: mode == ThemeMode.dark,
                  onChanged: (_) =>
                      ref.read(themeModeProvider.notifier).toggle(),
                  activeThumbColor: AppColors.cyan,
                  secondary: Icon(
                    mode == ThemeMode.dark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: p.highlight,
                  ),
                  title: Text(
                    'Dark mode',
                    style: AppTextStyles.cardHeading(p.primaryText),
                  ),
                  subtitle: Text(
                    mode == ThemeMode.dark ? 'On' : 'Off',
                    style: AppTextStyles.support(p.secondaryText),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Account, payments and settings are coming next.',
                style: AppTextStyles.support(p.secondaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
