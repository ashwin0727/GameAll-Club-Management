/// Every destination the Player app can open from the Home page. Pages that are not built yet open a clear "coming soon" page
/// (see `ComingSoonPage`), so a tap always goes somewhere.
class AppRoutes {
  const AppRoutes._();

  static const home = '/';
  static const guestBooking = '/guest-booking';
  static const memberships = '/memberships';
  static const myMembership = '/my-membership';
  static const coaching = '/coaching';
  static const myCoaching = '/my-coaching';
  static const bookings = '/bookings';
  static const explore = '/explore';
  static const profile = '/profile';
  static const search = '/search';
  static const notifications = '/notifications';
  static const tournaments = '/tournaments';
  static const howItWorks = '/how-it-works';
  static const login = '/login';
}

/// Opens a route. The Home widgets take one of these so a test can record the taps.
typedef RouteCallback = void Function(String route);
