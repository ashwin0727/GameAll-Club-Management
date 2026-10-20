/// Centralized corner-radius scale — every card/button/input/chip/sheet in
/// the app pulls from here instead of scattering literal radius values, so
/// the whole product reads as one consistent shape language.
class AppRadius {
  const AppRadius._();

  static const double xs = 4;
  static const double sm = 8;
  // Corrected from 10 → the spec's actual 12px token — a 2px nudge, not a
  // new value invented for this redesign (spec §"Radius System").
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double pill = 999;
}