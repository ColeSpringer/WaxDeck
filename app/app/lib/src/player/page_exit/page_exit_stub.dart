import 'page_exit_port.dart';

export 'page_exit_port.dart';

/// Native builds. The document lifecycle this is about is a browser's,
/// and the platforms that have a real one - a window closing, a task
/// swiped away - answer it with ordinary code that has time to finish.
PageExitPort createPageExitPort() => const NoPageExit();

class NoPageExit implements PageExitPort {
  const NoPageExit();

  @override
  void bind({
    required List<ExitRequest> Function() onExit,
    required List<ExitRequest> Function() onHidden,
  }) {}

  @override
  void dispose() {}
}
