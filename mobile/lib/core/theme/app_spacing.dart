/// Centralized spacing scale so screens don't scatter arbitrary padding
/// values. Logical pixels — Flutter already scales these correctly with
/// device pixel ratio; text/accessibility scaling is handled separately by
/// [MediaQuery.textScaler], never suppressed.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Minimum touch target per the platform accessibility guidance this
  /// project follows throughout (44dp minimum, 48dp preferred).
  static const double minTouchTarget = 48;
}