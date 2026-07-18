/// Hand-written repository layer over the generated WaxDeck API client.
///
/// App code imports this package only; the generated `waxdeck_api_gen`
/// package (dart-dio + built_value) is an implementation detail behind it,
/// so generator churn never ripples into feature code.
library;

export 'src/client.dart';
export 'src/models.dart';
export 'src/session_id.dart';
