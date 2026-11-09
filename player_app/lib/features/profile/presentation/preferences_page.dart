import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/external_links.dart';
import '../../../core/routing/app_routes.dart';
import '../../player_home/application/player_home_controller.dart';
import '../application/profile_providers.dart';
import 'profile_widgets.dart';

/// Preferences: which reminders to get, the language, and Dark / Light.
class PreferencesPage extends ConsumerWidget {
  const PreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final prefs = ref.watch(playerPrefsProvider);
    final ctl = ref.read(playerPrefsProvider.notifier);
    final mode = ref.watch(themeModeProvider);

    Widget toggle(
      Key key,
      IconData icon,
      String title,
      String subtitle,
      bool value,
      ValueChanged<bool> onChanged,
    ) => ProfileMenuRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: Switch(
        key: key,
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.cyan,
      ),
    );

    Widget modeChoice(ThemeMode m, IconData icon, String label) {
      final on = mode == m;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            key: ValueKey('pref-theme-${m.name}'),
            onTap: () => ref.read(themeModeProvider.notifier).set(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: on
                    ? const LinearGradient(
                        colors: [Color(0xFF9B5CFF), Color(0xFF5B5BE8)],
                      )
                    : null,
                border: Border.all(color: on ? Colors.transparent : p.border),
              ),
              child: Column(
                children: [
                  Icon(icon, color: on ? Colors.white : p.secondaryText),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: AppTextStyles.button(
                      on ? Colors.white : p.primaryText,
                    ).copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ProfileSubPage(
      title: 'Preferences',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileColumns(
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProfileSectionTitle('Notifications'),
                ProfilePanel(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      toggle(
                        const ValueKey('pref-booking'),
                        Icons.event_available_outlined,
                        'Booking reminders',
                        'Before your court booking, coaching session or membership slot',
                        prefs.bookingReminders,
                        ctl.setBooking,
                      ),
                      const ProfileDivider(),
                      toggle(
                        const ValueKey('pref-payment'),
                        Icons.payments_outlined,
                        'Payment reminders',
                        'When a payment or a balance is still pending',
                        prefs.paymentReminders,
                        ctl.setPayment,
                      ),
                      const ProfileDivider(),
                      toggle(
                        const ValueKey('pref-offers'),
                        Icons.local_offer_outlined,
                        'Offers & updates',
                        'New venues, plans and offers near you',
                        prefs.offers,
                        ctl.setOffers,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    'Your notifications are listed on the bell on Home.',
                    style: AppTextStyles.support(p.mutedText),
                  ),
                ),
              ],
            ),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProfileSectionTitle('Language'),
                ProfilePanel(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ProfileMenuRow(
                    icon: Icons.translate_rounded,
                    title: 'English',
                    subtitle: 'More languages are coming soon',
                    onTap: null,
                    trailing: const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                    ),
                  ),
                ),
                const ProfileSectionTitle('Appearance'),
                ProfilePanel(
                  child: Row(
                    children: [
                      modeChoice(
                        ThemeMode.dark,
                        Icons.dark_mode_rounded,
                        'Dark',
                      ),
                      const SizedBox(width: 12),
                      modeChoice(
                        ThemeMode.light,
                        Icons.light_mode_rounded,
                        'Light',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Support & Legal: help, the policies, deleting the account, and the app version.
class SupportLegalPage extends ConsumerWidget {
  const SupportLegalPage({super.key, required this.onNavigate});

  final void Function(String route) onNavigate;

  static const supportEmail = 'admin@gameall.co';
  static const supportPhone = '9360428761';
  static const site = 'https://gameall.co';
  static const version = '1.0.0';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    Future<void> open(Uri uri) async {
      final ok = await ref.read(linkOpenerProvider)(uri);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("We couldn't open that. Please try again."),
          ),
        );
      }
    }

    return ProfileSubPage(
      title: 'Support & Legal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileColumns(
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProfileSectionTitle('Help'),
                ProfilePanel(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      ProfileMenuRow(
                        key: const ValueKey('sl-email'),
                        icon: Icons.mail_outline_rounded,
                        title: 'Email support',
                        subtitle: supportEmail,
                        onTap: () => open(
                          Uri(
                            scheme: 'mailto',
                            path: supportEmail,
                            query: 'subject=GameAll Play support',
                          ),
                        ),
                      ),
                      const ProfileDivider(),
                      ProfileMenuRow(
                        key: const ValueKey('sl-call'),
                        icon: Icons.call_outlined,
                        title: 'Call us',
                        subtitle: '+91 $supportPhone',
                        onTap: () =>
                            open(Uri(scheme: 'tel', path: '+91$supportPhone')),
                      ),
                      const ProfileDivider(),
                      ProfileMenuRow(
                        key: const ValueKey('sl-how'),
                        icon: Icons.help_outline_rounded,
                        title: 'How GameAll works',
                        subtitle: 'Booking, memberships, coaching and payments',
                        onTap: () {
                          Navigator.of(context).pop();
                          onNavigate(AppRoutes.howItWorks);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProfileSectionTitle('Legal'),
                ProfilePanel(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      ProfileMenuRow(
                        key: const ValueKey('sl-terms'),
                        icon: Icons.description_outlined,
                        title: 'Terms & Conditions',
                        subtitle: 'The rules for using GameAll',
                        onTap: () => open(Uri.parse('$site/terms')),
                      ),
                      const ProfileDivider(),
                      ProfileMenuRow(
                        key: const ValueKey('sl-privacy'),
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy Policy',
                        subtitle: 'What we keep and why',
                        onTap: () => open(Uri.parse('$site/privacy')),
                      ),
                      const ProfileDivider(),
                      ProfileMenuRow(
                        key: const ValueKey('sl-delete'),
                        icon: Icons.delete_outline_rounded,
                        title: 'Delete my account',
                        subtitle: 'How to remove your account and data',
                        danger: true,
                        onTap: () => open(Uri.parse('$site/delete-account')),
                      ),
                    ],
                  ),
                ),
                const ProfileSectionTitle('About'),
                ProfilePanel(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ProfileMenuRow(
                    icon: Icons.info_outline_rounded,
                    title: 'GameAll Play',
                    subtitle: 'Version $version',
                    onTap: null,
                    trailing: const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '© GameAll',
                    style: AppTextStyles.support(p.mutedText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
