/// Reports — a small icon + accent lookup for sport names, used by the
/// Court Utilization report's "By Sport" cards and court list so each sport
/// reads as a distinct, colour-coded glyph rather than a plain row of text.
///
/// The accent is a raw colour, not a token — [AppColorTokens.accentFill] /
/// [AppColorTokens.accentSolid] deepen or lighten it correctly for whichever
/// theme is active, so one colour here already works in both modes.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class SportVisual {
  const SportVisual(this.icon, this.accent);

  final IconData icon;
  final Color accent;
}

const _cricketAccent = Color(0xFFE8834B);

const _fallbackPalette = [
  Color(0xFF00C77A),
  Color(0xFF7E93FF),
  Color(0xFFA98CFF),
  Color(0xFFE8834B),
  Color(0xFF2ED993),
];

const _fallbackIcons = [
  Icons.sports_kabaddi,
  Icons.sports_handball,
  Icons.sports_hockey,
  Icons.sports_volleyball,
];

/// Looks up a badge for [sportName]. Unrecognised names still get a stable
/// icon/colour pair (hashed from the name) instead of a generic placeholder,
/// so a facility running a sport outside this list still reads consistently
/// across the report.
SportVisual sportVisual(AppColorTokens tokens, String sportName) {
  final n = sportName.toLowerCase();
  if (n.contains('badminton')) return SportVisual(Icons.sports_tennis, tokens.primary);
  if (n.contains('cricket')) return const SportVisual(Icons.sports_cricket, _cricketAccent);
  if (n.contains('pickleball')) return SportVisual(Icons.sports_baseball, tokens.electricBlue);
  if (n.contains('tennis')) return SportVisual(Icons.sports_tennis, tokens.violet);
  if (n.contains('squash')) return SportVisual(Icons.sports_tennis, tokens.violet);
  if (n.contains('football') || n.contains('soccer')) return SportVisual(Icons.sports_soccer, tokens.info);
  if (n.contains('basketball')) return SportVisual(Icons.sports_basketball, tokens.warning);
  if (n.contains('volleyball')) return SportVisual(Icons.sports_volleyball, tokens.success);
  if (n.contains('hockey')) return SportVisual(Icons.sports_hockey, tokens.destructive);
  if (n.contains('turf') || n.contains('futsal')) return const SportVisual(Icons.grass, Color(0xFF2ED993));

  final idx = sportName.hashCode.abs();
  return SportVisual(_fallbackIcons[idx % _fallbackIcons.length], _fallbackPalette[idx % _fallbackPalette.length]);
}
