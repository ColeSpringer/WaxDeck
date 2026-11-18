/// The audits that read `lib/` through the analyzer, in one process: each
/// would otherwise link the element model of every dependency, which costs
/// more than all their work after it.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';

import 'account_scoping_audit.dart';
import 'account_scoping_cases.dart';
import 'analysis_host.dart';
import 'bare_pop_audit.dart';
import 'bare_replace_audit.dart';
import 'destination_push_audit.dart';
import 'extension_tear_off_audit.dart';
import 'page_messages_audit.dart';
import 'theme_landing_audit.dart';

void main() {
  AnalysisHost? host;
  setUpAll(() async {
    final opened = host = AnalysisHost();
    await opened.session.getLibraryByUri('package:waxdeck/src/providers.dart');
  });
  tearDownAll(() async => host?.dispose());

  AnalysisHost shared() => host!;
  accountScopingAudit(shared);
  accountScopingCases(shared);
  barePopAudit(shared);
  bareReplaceAudit(shared);
  destinationPushAudit(shared);
  extensionTearOffAudit(shared);
  pageMessagesAudit(shared);
  themeLandingAudit(shared);
}
