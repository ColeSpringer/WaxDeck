/// The audits that read `lib/` through the analyzer, in one process: each
/// would otherwise link the element model of every dependency, which costs
/// more than all their work after it.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';

import 'account_scoping_audit.dart';
import 'account_scoping_cases.dart';
import 'analysis_host.dart';
import 'extension_tear_off_audit.dart';

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
  extensionTearOffAudit(shared);
}
