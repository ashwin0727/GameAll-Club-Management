/// Screen-width classes, in Flutter logical pixels — never tied to a
/// specific device model. Everything in this app that needs a width-based
/// decision goes through [ScreenSize.of], not an ad-hoc `if (width < 400)`
/// scattered through widgets (item 12).
enum ScreenSize { small, medium, large }

class Breakpoints {
  const Breakpoints._();

  /// Below this, treat as a small/narrow phone (e.g. ~320-359dp).
  static const double small = 360;

  /// Below this, a typical phone (e.g. ~360-479dp); at/above, a large phone
  /// or small tablet, which gets extra layout room.
  static const double large = 480;

  static ScreenSize classify(double width) {
    if (width < small) return ScreenSize.small;
    if (width < large) return ScreenSize.medium;
    return ScreenSize.large;
  }

  /// Content on very wide screens (large phones in landscape, tablets)
  /// shouldn't stretch edge to edge — see item 49.
  static const double maxContentWidth = 640;
}