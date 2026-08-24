/// Centralized corner-radius scale — every card/button/input/chip/sheet in
/// the app pulls from here instead of scattering literal radius values, so
/// the whole product reads as one consistent shape language.
class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 10;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}