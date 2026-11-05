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

  /// A venue's own page: `/venue/<id>`.
  static const venue = '/venue';
  static String venuePath(String id) => '$venue/$id';

  /// The venue id in a `/venue/<id>` route, or null when [route] is not one.
  /// A venue's Enroll Membership page: `/enroll/<id>`.
  static const enroll = '/enroll';
  static String enrollPath(String id) => '$enroll/$id';
  static String? enrollVenueIdOf(String route) => route.startsWith('$enroll/') && route.length > enroll.length + 1 ? route.substring(enroll.length + 1) : null;

  /// A venue's Book a Court page: `/book/<id>`.
  static const book = '/book';
  static String bookPath(String id) => '$book/$id';

  /// The venue id in a `/book/<id>` route, or null when [route] is not one.
  static String? bookVenueIdOf(String route) => route.startsWith('$book/') && route.length > book.length + 1 ? route.substring(book.length + 1) : null;

  static String? venueIdOf(String route) => route.startsWith('$venue/') && route.length > venue.length + 1 ? route.substring(venue.length + 1) : null;
}

/// Opens a route. The Home widgets take one of these so a test can record the taps.
typedef RouteCallback = void Function(String route);
