// An engine that can say which developer it develops on. The native engine does; a browser
// engine has its own, so the editor asks with `is EngineBackend` rather than on the interface
// every engine and test fake must implement.
abstract interface class EngineBackend {
  /// The developer, as `fotufilm_engine_describe` names it: "vulkan", "cuda" or "cpu".
  String get backend;
}
