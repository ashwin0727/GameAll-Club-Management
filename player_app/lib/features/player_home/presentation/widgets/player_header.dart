import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

/// The GameAll logo (the wordmark). White on the dark theme, dark navy on the light theme; the cyan and purple triangles stay.
class GameAllLogo extends StatelessWidget {
  const GameAllLogo({super.key, this.height = 40});
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    return Semantics(
      label: 'GameAll',
      child: ExcludeSemantics(
        child: Image.asset(
          dark
              ? 'assets/images/gameall_logo.webp'
              : 'assets/images/gameall_logo_dark.webp',
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

/// A bell with a red dot (or a count) when there is something unread.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.unread,
    required this.onPressed,
  });
  final int unread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
      child: ExcludeSemantics(
        child: InkResponse(
          onTap: onPressed,
          radius: 28,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 26,
                  color: p.primaryText,
                ),
                if (unread > 0)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 9,
                        minHeight: 9,
                      ),
                      padding: unread > 9
                          ? const EdgeInsets.symmetric(horizontal: 4)
                          : EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: p.background, width: 1.5),
                      ),
                      child: unread > 9
                          ? Text(
                              '9+',
                              style: AppTextStyles.meta(Colors.white)
                                  .copyWith(fontSize: 9),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo, notifications, and the greeting ("Hi, Alex 👋").
class PlayerHeader extends StatelessWidget {
  const PlayerHeader({
    super.key,
    required this.firstName,
    required this.unread,
    required this.onNotifications,
  });

  final String firstName;
  final int unread;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const GameAllLogo(),
              NotificationBell(unread: unread, onPressed: onNotifications),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // The name arrives after the data: cross-fade it in place (same line, same height) instead of swapping the text abruptly.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          // An icon, not the 👋 emoji: the web emoji font loads late and showed an empty box on refresh.
          child: Row(
            key: ValueKey(firstName),
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Hi, $firstName',
                  style: AppTextStyles.greeting(p.primaryText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.waving_hand_rounded, size: 20, color: Color(0xFFFFC857)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Ready to play today?',
          style: AppTextStyles.body(p.secondaryText),
        ),
      ],
    );
  }
}
