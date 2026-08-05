import 'share_card_export.dart';

/// A platform with neither a filesystem nor a share sheet. Nothing
/// reaches this today; it exists so the conditional import has a
/// default that compiles.
ShareCardExporter createShareCardExporter() => const InertShareCardExporter();
