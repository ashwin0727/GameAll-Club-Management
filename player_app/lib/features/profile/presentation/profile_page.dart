import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/top_toast.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/presentation/login_flow.dart';
import '../../player_home/application/player_home_controller.dart';
import '../application/profile_providers.dart';
import '../data/profile_repository.dart';
import '../domain/profile_models.dart';
import 'activity_history_page.dart';
import 'payments_billing_page.dart';
import 'personal_info_page.dart';
import 'preferences_page.dart';
import 'profile_widgets.dart';

/// Shares text with the system share sheet. Tests replace it.
typedef ProfileSharer = Future<void> Function(String text);

final profileSharerProvider = Provider<ProfileSharer>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  },
);

/// Picks a photo from the gallery: its bytes and file extension, or null when cancelled. Tests replace it.
typedef PhotoPicker = Future<(Uint8List, String)?> Function();

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => () async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return null;
    final name = file.name.toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : 'jpg';
    return (await file.readAsBytes(), ext);
  },
);

/// My Profile: the person, their four totals, the five areas (Personal Information, Payment & Billing, Activity & History,
/// Preferences, Support & Legal) and Log out.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, required this.onNavigate});

  /// Opens a route of the app (the shell's own).
  final void Function(String route) onNavigate;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _uploading = false;

  void _say(String text) {
    if (!mounted) return;
    TopToast.of(context, text);
  }

  void _open(Widget page) {
    Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => page))
        .then((_) {
          if (!mounted) return;
          ref.invalidate(profileDetailsProvider);
          ref.invalidate(profileStatsProvider);
        });
  }

  Future<void> _changePhoto() async {
    final picker = ref.read(photoPickerProvider);
    final repo = ref.read(profileRepositoryProvider);
    try {
      final picked = await picker();
      if (picked == null) return;
      setState(() => _uploading = true);
      await repo.uploadAvatar(picked.$1, picked.$2);
      ref.invalidate(profileDetailsProvider);
      _say('Photo updated.');
    } on ProfileFailure catch (e) {
      _say(e.message);
    } catch (_) {
      _say("We couldn't use that photo. Please try another.");
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _copyId(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    _say('Player ID copied.');
  }

  Future<void> _share(ProfileDetails d) async {
    final text =
        'Play with me on GameAll! My Player ID is ${d.playerCode ?? ''}. Book courts, join memberships and find coaching: https://play.gameall.co';
    try {
      await ref.read(profileSharerProvider)(text);
    } catch (_) {
      // no share sheet here (a desktop browser): copy the message instead
      await Clipboard.setData(ClipboardData(text: text));
      _say('Copied. You can paste it anywhere.');
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You can log back in with your mobile number any time.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('logout-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('logout-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final player = ref.watch(currentPlayerProvider);
    // On a refresh the sign-in is still being restored for a moment: that is not "signed out" (no Login card), the page just waits
    final auth = ref.watch(authControllerProvider);
    final authLoading = auth.isLoading && !auth.hasValue;
    final detailsAsync = ref.watch(profileDetailsProvider);
    final details = detailsAsync.value;
    // on a refresh the real profile takes a moment: show a quiet placeholder, not the sign-in stand-in (wrong Player ID, no photo)
    final detailsLoading = detailsAsync.isLoading && !detailsAsync.hasValue;
    final stats = ref.watch(profileStatsProvider);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppDimensions.desktopBreakpoint;

    final title = Text(
      'My Profile',
      key: const ValueKey('profile-title'),
      style: AppTextStyles.sectionHeading(p.primaryText),
    );

    Widget body;
    if (player == null && !authLoading) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SignedOutCard(onLogin: () => showPlayerLogin(context)),
          const SizedBox(height: 14),
          _ThemeSwitchCard(),
        ],
      );
    } else {
      final me = details ?? (player == null ? null : ProfileDetails.fromBasic(player));
      final Widget header = detailsLoading || authLoading || me == null
          ? const _HeaderSkeleton()
          : _HeaderCard(
        details: me,
        uploading: _uploading,
        onPhoto: _changePhoto,
        onCopy: _copyId,
        onEdit: () => _open(const PersonalInfoPage()),
        onShare: () => _share(me),
      );
      final statsCard = _StatsCard(
        stats: stats.value,
        loading: authLoading || (stats.isLoading && !stats.hasValue),
        onTap: (route) => widget.onNavigate(route),
      );
      final menu = ProfilePanel(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            ProfileMenuRow(
              key: const ValueKey('menu-personal'),
              icon: Icons.person_outline_rounded,
              title: 'Personal Information',
              subtitle: 'Name, DOB, gender, location',
              onTap: () => _open(const PersonalInfoPage()),
            ),
            const ProfileDivider(),
            ProfileMenuRow(
              key: const ValueKey('menu-payments'),
              icon: Icons.credit_card_outlined,
              title: 'Payment & Billing',
              subtitle: 'Payments, invoices, refunds',
              onTap: () => _open(const PaymentsBillingPage()),
            ),
            const ProfileDivider(),
            ProfileMenuRow(
              key: const ValueKey('menu-activity'),
              icon: Icons.bar_chart_rounded,
              title: 'Activity & History',
              subtitle: 'Bookings, tournaments & stats',
              onTap: () =>
                  _open(ActivityHistoryPage(onNavigate: widget.onNavigate)),
            ),
            const ProfileDivider(),
            ProfileMenuRow(
              key: const ValueKey('menu-preferences'),
              icon: Icons.settings_outlined,
              title: 'Preferences',
              subtitle: 'Notifications, language & appearance',
              onTap: () => _open(const PreferencesPage()),
            ),
            const ProfileDivider(),
            ProfileMenuRow(
              key: const ValueKey('menu-support'),
              icon: Icons.headset_mic_outlined,
              title: 'Support & Legal',
              subtitle: 'Help, terms, privacy & app info',
              onTap: () =>
                  _open(SupportLegalPage(onNavigate: widget.onNavigate)),
            ),
          ],
        ),
      );
      final logout = Pressable(
        key: const ValueKey('profile-logout'),
        onTap: _logout,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: AppColors.danger.withValues(alpha: 0.8),
              width: 1.5,
            ),
            color: AppColors.danger.withValues(alpha: 0.08),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.logout_rounded,
                size: 20,
                color: AppColors.danger,
              ),
              const SizedBox(width: 10),
              Text('Logout', style: AppTextStyles.button(AppColors.danger)),
            ],
          ),
        ),
      );
      // wide (the web): the person and the totals on the left, the five areas and Logout on the right, so the page uses the width;
      // a phone: one column
      body = wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [header, const SizedBox(height: 16), statsCard],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [menu, const SizedBox(height: 16), logout],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 14),
                statsCard,
                const SizedBox(height: 14),
                menu,
                const SizedBox(height: 16),
                logout,
              ],
            );
    }

    final side = wide
        ? AppDimensions.desktopSidePadding(width)
        : AppDimensions.screenPadding;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ListView(
          key: const ValueKey('profile-scroll'),
          padding: EdgeInsets.fromLTRB(side, wide ? 24 : 10, side, 32),
          children: [
            title,
            SizedBox(height: wide ? 20 : 16),
            body,
          ],
        ),
      ),
    );
  }
}

class _SignedOutCard extends StatelessWidget {
  const _SignedOutCard({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ProfilePanel(
      child: Column(
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
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.details,
    required this.uploading,
    required this.onPhoto,
    required this.onCopy,
    required this.onEdit,
    required this.onShare,
  });

  final ProfileDetails details;
  final bool uploading;
  final VoidCallback onPhoto;
  final void Function(String code) onCopy;
  final VoidCallback onEdit;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = details;

    Widget line(IconData icon, String text, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: p.secondaryText),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              key: key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.support(p.secondaryText),
            ),
          ),
        ],
      ),
    );

    final avatar = SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            key: const ValueKey('profile-avatar'),
            width: 92,
            height: 92,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.brandGradient,
            ),
            child: ClipOval(
              child: d.avatarUrl == null
                  ? Container(
                      color: p.surface,
                      alignment: Alignment.center,
                      child: Text(
                        d.initials,
                        style: AppTextStyles.sectionHeading(p.primaryText),
                      ),
                    )
                  : Image.network(
                      d.avatarUrl!,
                      width: 86,
                      height: 86,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: p.surface,
                        alignment: Alignment.center,
                        child: Text(
                          d.initials,
                          style: AppTextStyles.sectionHeading(p.primaryText),
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Semantics(
              button: true,
              label: 'Change photo',
              child: Pressable(
                key: const ValueKey('profile-photo-button'),
                onTap: uploading ? null : onPhoto,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF6D3FE0),
                    border: Border.all(color: p.background, width: 2),
                  ),
                  child: uploading
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.photo_camera_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                d.fullName,
                key: const ValueKey('profile-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.sectionHeading(p.primaryText)
                    .copyWith(fontSize: 20),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.verified_rounded,
              size: 18,
              color: Color(0xFF9B5CFF),
            ),
          ],
        ),
        if (d.playerCode != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'Player ID: ${d.playerCode}',
                    key: const ValueKey('profile-player-id'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.support(p.secondaryText),
                  ),
                ),
                InkResponse(
                  key: const ValueKey('profile-copy-id'),
                  onTap: () => onCopy(d.playerCode!),
                  radius: 18,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: p.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        line(
          Icons.call_outlined,
          '+91 ${d.phone}',
          key: const ValueKey('profile-phone'),
        ),
        if (d.email != null)
          line(
            Icons.mail_outline_rounded,
            d.email!,
            key: const ValueKey('profile-email'),
          ),
      ],
    );

    Widget action(
      String key,
      IconData icon,
      String label,
      VoidCallback onTap,
    ) => Expanded(
      child: Pressable(
        key: ValueKey(key),
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: p.isDark ? const Color(0xFF3A4A78) : p.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: p.primaryText),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppTextStyles.button(p.primaryText)
                        .copyWith(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return ProfilePanel(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 16),
              Expanded(child: info),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              action(
                'profile-edit',
                Icons.edit_outlined,
                'Edit Profile',
                onEdit,
              ),
              const SizedBox(width: 12),
              action('profile-share', Icons.share_outlined, 'Share', onShare),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the header card shows for the moment the profile is being read: the same shape, softly pulsing.
class _HeaderSkeleton extends StatefulWidget {
  const _HeaderSkeleton();

  @override
  State<_HeaderSkeleton> createState() => _HeaderSkeletonState();
}

class _HeaderSkeletonState extends State<_HeaderSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = p.isDark ? const Color(0xFF1B2A4D) : p.secondaryBackground;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(8)),
    );
    return ProfilePanel(
      child: FadeTransition(
        key: const ValueKey('profile-header-loading'),
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(width: 96, height: 96, decoration: BoxDecoration(shape: BoxShape.circle, color: tone)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(150, 20),
                      const SizedBox(height: 12),
                      bar(190, 12),
                      const SizedBox(height: 10),
                      bar(150, 12),
                      const SizedBox(height: 10),
                      bar(170, 12),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Container(height: 48, decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(24)))),
                const SizedBox(width: 12),
                Expanded(child: Container(height: 48, decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(24)))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.stats,
    required this.loading,
    required this.onTap,
  });

  final ProfileStats? stats;
  final bool loading;
  final void Function(String route) onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    String n(int? v) => loading ? '' : (v == null ? '—' : '$v');

    Widget cell(
      String key,
      IconData icon,
      Color tint,
      String value,
      String label,
      String route,
    ) => Expanded(
      child: Semantics(
        button: true,
        label: '$label ${value.isEmpty ? '' : value}',
        child: ExcludeSemantics(
          child: Pressable(
            key: ValueKey(key),
            onTap: () => onTap(route),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Icon(icon, size: 26, color: tint),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 24,
                    child: value.isEmpty
                        ? const Center(
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Text(
                            value,
                            style: AppTextStyles.sectionHeading(p.primaryText)
                                .copyWith(fontSize: 20),
                          ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: AppTextStyles.support(p.secondaryText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return ProfilePanel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: [
          cell(
            'stat-bookings',
            Icons.calendar_month_outlined,
            const Color(0xFF8B8BFF),
            n(stats?.bookings),
            'Bookings',
            AppRoutes.bookings,
          ),
          cell(
            'stat-memberships',
            Icons.workspace_premium_outlined,
            const Color(0xFFFFC061),
            n(stats?.memberships),
            'Memberships',
            AppRoutes.myMembership,
          ),
          cell(
            'stat-coaching',
            Icons.school_outlined,
            AppColors.cyan,
            n(stats?.coaching),
            'Coaching',
            AppRoutes.myCoaching,
          ),
          cell(
            'stat-tournaments',
            Icons.emoji_events_outlined,
            const Color(0xFFD16BFF),
            n(stats?.tournaments),
            'Tournaments',
            AppRoutes.tournaments,
          ),
        ],
      ),
    );
  }
}

/// Dark mode on / off, for someone who is not signed in (signed-in players have Appearance under Preferences).
class _ThemeSwitchCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final mode = ref.watch(themeModeProvider);
    return ProfilePanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile(
          key: const ValueKey('theme-switch'),
          value: mode == ThemeMode.dark,
          onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
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
    );
  }
}
