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

  /// The rest of the spec's full 4px scale (4·8·12·16·20·24·32·40·48·64) —
  /// additive only, so no existing screen's spacing shifts. `lg2` fills the
  /// 16→24 gap the original xs/sm/md/lg/xl/xxl names skipped.
  static const double lg2 = 20;
  static const double xxxl = 40;
  static const double huge = 48;
  static const double massive = 64;

  /// Minimum touch target per the platform accessibility guidance this
  /// project follows throughout (44dp minimum, 48dp preferred).
  static const double minTouchTarget = 48;
}