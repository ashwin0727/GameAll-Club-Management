import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum AppAvatarSize { small, medium, large }

/// Image avatar with an initials fallback (spec §"Avatar System") — never
/// a blank circle while an image loads/fails, never oversized.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, this.imageUrl, this.size = AppAvatarSize.medium});

  final String name;
  final String? imageUrl;
  final AppAvatarSize size;

  double get _diameter {
    switch (size) {
      case AppAvatarSize.small:
        return 32;
      case AppAvatarSize.medium:
        return 44;
      case AppAvatarSize.large:
        return 64;
    }
  }

  double get _fontSize {
    switch (size) {
      case AppAvatarSize.small:
        return 12;
      case AppAvatarSize.medium:
        return 16;
      case AppAvatarSize.large:
        return 22;
    }
  }

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Semantics(
      label: name,
      image: hasImage,
      child: ClipOval(
        child: Container(
          width: _diameter,
          height: _diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tokens.surface2, border: Border.all(color: tokens.borderColor)),
          child: hasImage
              ? Image.network(
                  imageUrl!,
                  width: _diameter,
                  height: _diameter,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) => progress == null ? child : _InitialsFallback(initials: _initials, fontSize: _fontSize),
                  errorBuilder: (context, error, stack) => _InitialsFallback(initials: _initials, fontSize: _fontSize),
                )
              : _InitialsFallback(initials: _initials, fontSize: _fontSize),
        ),
      ),
    );
  }
}

class _InitialsFallback extends StatelessWidget {
  const _InitialsFallback({required this.initials, required this.fontSize});

  final String initials;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      initials,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: context.tokens.primary),
    );
  }
}