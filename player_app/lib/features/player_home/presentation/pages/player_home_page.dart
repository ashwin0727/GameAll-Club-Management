import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/reveal.dart';
import '../../../../core/widgets/gameall_buttons.dart';
import '../../../auth/application/auth_providers.dart';
import '../../application/player_home_controller.dart';
import '../../domain/player_home_models.dart';
import '../widgets/home_promo_carousel.dart';
import '../widgets/next_game_section.dart';
import '../widgets/player_header.dart';
import '../widgets/player_search_bar.dart';
import '../widgets/player_shortcut_card.dart';
import '../widgets/sports_selector.dart';
import '../widgets/payment_prompts.dart';
import '../widgets/player_dashboard.dart';
import 'player_dashboard_desktop.dart';
import 'player_home_desktop.dart';

/// The Player Home page. On a phone (or any narrow window) it is the single scrolling column of the mobile design; on a wide
/// window (the web) it becomes the desktop layout. Both are built from the same widgets and the same data.
class PlayerHomePage extends ConsumerWidget {
  const PlayerHomePage({
    super.key,
    required this.onNavigate,
    this.now,
    this.desktopHeader,
  });

  final RouteCallback onNavigate;

  /// The brand bar of the wide layout. It is placed at the top of the scrolling content, so it scrolls away with the page.
  final Widget? desktopHeader;

  /// For tests; the real clock otherwise.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(playerHomeProvider);
    final sport = ref.watch(selectedSportProvider);
    final data = home.value ?? const PlayerHomeData.guest();
    final loading = home.isLoading && !home.hasValue;
    final failed = home.hasError && !home.hasValue;
    final sportName = sportOptions.firstWhere((s) => s.id == sport).sportName;
    final next = resolveNextGame(
      data,
      now ?? DateTime.now(),
      sportName: sportName,
    );

    final wide =
        MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;

    // A player who is already signed in must never see the visitor's Home, not even for a moment while the page reloads. When a
    // session exists, the page waits (with a placeholder shaped like the dashboard) until the player's own data is here.
    final hasSession = ref.watch(playerAuthRepositoryProvider).isSignedIn;
    final auth = ref.watch(authControllerProvider);
    final waitingForPlayer =
        hasSession &&
        (auth.isLoading ||
            (home.isLoading && !(home.hasValue && data.signedIn)));
    if (waitingForPlayer) {
      return _SignedInPlaceholder(wide: wide, header: desktopHeader);
    }

    final body = wide && data.signedIn
        ? PlayerDashboardDesktop(
            data: data,
            onNavigate: onNavigate,
            header: desktopHeader,
            now: now,
          )
        : wide
        ? PlayerHomeDesktopBody(
            data: data,
            next: next,
            loading: loading,
            onNavigate: onNavigate,
            now: now,
            header: desktopHeader,
          )
        : _PhoneBody(
            data: data,
            next: next,
            loading: loading,
            failed: failed,
            onNavigate: onNavigate,
            now: now,
          );

    // No cross-fade between the placeholder and the page: both carry the brand bar, and fading one over the other would show two bars
    // at once. The page's own pieces fade in one after another instead (Reveal), which is what makes it arrive smoothly.
    return RefreshIndicator(
      onRefresh: () => ref.read(playerHomeProvider.notifier).refresh(),
      color: AppColors.cyan,
      child: body,
    );
  }
}

/// What a signed-in player sees for the moment their Home is loading: the same shapes as the dashboard (welcome, three cards, two
/// panels), softly pulsing. Content then fades in over it, so the page never shows the wrong screen first.
class _SignedInPlaceholder extends StatelessWidget {
  const _SignedInPlaceholder({required this.wide, this.header});

  final bool wide;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!wide) {
      return SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            12,
            AppDimensions.screenPadding,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.surface,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(child: _Skeleton(height: 44)),
                ],
              ),
              const SizedBox(height: 20),
              const _Skeleton(height: 104),
              const SizedBox(height: 12),
              const _Skeleton(height: 104),
              const SizedBox(height: 12),
              const _Skeleton(height: 104),
              const SizedBox(height: 16),
              const _Skeleton(height: 180),
            ],
          ),
        ),
      );
    }
    final side = AppDimensions.desktopSidePadding(
      MediaQuery.sizeOf(context).width,
    );
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?header,
          Padding(
            padding: EdgeInsets.fromLTRB(side, 12, side, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.surface,
                      ),
                    ),
                    const SizedBox(width: 18),
                    const SizedBox(width: 320, child: _Skeleton(height: 64)),
                  ],
                ),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Expanded(child: _Skeleton(height: 128)),
                    SizedBox(width: 18),
                    Expanded(child: _Skeleton(height: 128)),
                    SizedBox(width: 18),
                    Expanded(child: _Skeleton(height: 128)),
                  ],
                ),
                const SizedBox(height: 22),
                const Row(
                  children: [
                    Expanded(flex: 11, child: _Skeleton(height: 150)),
                    SizedBox(width: 20),
                    Expanded(flex: 9, child: _Skeleton(height: 150)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneBody extends ConsumerWidget {
  const _PhoneBody({
    required this.data,
    required this.next,
    required this.loading,
    required this.failed,
    required this.onNavigate,
    this.now,
  });

  final PlayerHomeData data;
  final NextGame next;
  final bool loading;
  final bool failed;
  final RouteCallback onNavigate;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    const gap = AppDimensions.sectionSpacing;
    return Stack(
      children: [
        // The only decoration: a faint blue light in the top-right corner. Everything else is flat navy.
        Positioned(
          top: -120,
          right: -120,
          child: IgnorePointer(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.blue.withValues(alpha: p.isDark ? 0.16 : 0.10),
                    AppColors.blue.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppDimensions.phoneMaxWidth,
                    ),
                    child: _FadeIn(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimensions.screenPadding,
                          4,
                          AppDimensions.screenPadding,
                          24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Reveal(
                              child: PlayerHeader(
                                firstName: loading ? '' : data.firstName,
                                unread: data.unreadNotifications,
                                onNotifications: () =>
                                    onNavigate(AppRoutes.notifications),
                              ),
                            ),
                            if (failed) ...[
                              const SizedBox(height: 12),
                              _ErrorBanner(
                                onRetry: () =>
                                    ref.invalidate(playerHomeProvider),
                              ),
                            ],
                            const SizedBox(height: gap),
                            Reveal(
                              delay: const Duration(milliseconds: 32),
                              child: PlayerSearchBar(
                                onSearch: () => onNavigate(AppRoutes.search),
                              ),
                            ),
                            const SizedBox(height: gap),
                            Reveal(
                              delay: const Duration(milliseconds: 64),
                              child: SportsSelector(
                                onMore: () => onNavigate(AppRoutes.explore),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Reveal(
                              delay: const Duration(milliseconds: 96),
                              child: HomePromoCarousel(onNavigate: onNavigate),
                            ),
                            const SizedBox(height: gap),
                            // When the data arrives the placeholder is replaced by the real content with a short fade; the height change is
                            // eased (AnimatedSize), never a jump.
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              alignment: Alignment.topCenter,
                              child: loading
                                  ? const _Skeleton(
                                      height: AppDimensions.shortcutHeight,
                                    )
                                  : Reveal(
                                      dy: 0,
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      child: PlayerShortcutCards(
                                        hasActiveMembership:
                                            data.hasActiveMembership,
                                        hasActiveCoaching:
                                            data.hasActiveCoaching,
                                        hasGuestBookings:
                                            data.hasBookingHistory,
                                        onNavigate: onNavigate,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 24),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              alignment: Alignment.topCenter,
                              child: loading
                                  ? const _Skeleton(height: 108)
                                  : Reveal(
                                      dy: 0,
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      child: NextGameSection(
                                        next: next,
                                        onNavigate: onNavigate,
                                        now: now,
                                      ),
                                    ),
                            ),
                            // A signed-in player also sees every active membership and coaching enrolment, the week's schedule and
                            // today's courts, found by their phone number at every club.
                            if (data.signedIn) ...[
                              const SizedBox(height: 24),
                              if (data.pendingPayments.isNotEmpty) ...[
                                PaymentPrompts(payments: data.pendingPayments, onNavigate: onNavigate),
                                const SizedBox(height: 12),
                              ],
                              Reveal(
                                child: DashboardSummaryCards(
                                  data: data,
                                  onNavigate: onNavigate,
                                  vertical: true,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Reveal(
                                delay: const Duration(milliseconds: 40),
                                child: ScheduleCard(
                                  items: data.schedule,
                                  now: now,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A 250ms fade when the page first appears.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
    builder: (context, v, child) => Opacity(opacity: v, child: child),
    child: child,
  );
}

/// A softly pulsing placeholder while data loads.
class _Skeleton extends StatefulWidget {
  const _Skeleton({required this.height});
  final double height;

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        key: const ValueKey('skeleton'),
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: AppDimensions.cardBorderRadius,
          color: Color.lerp(p.surface, p.elevated, _c.value),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const ValueKey('home-error'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "We couldn't load your details.",
              style: AppTextStyles.support(p.primaryText),
            ),
          ),
          GameAllButton.secondary(
            label: 'Retry',
            onPressed: onRetry,
            height: 36,
          ),
        ],
      ),
    );
  }
}
