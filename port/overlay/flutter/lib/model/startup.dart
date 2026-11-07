// How far the engine has come at launch (what `prepare` reports), for the startup progress card
// over the empty viewer.

class StartupState {
  const StartupState(this.value, this.label, {this.done = false});
  final double value;
  final String label;
  final bool done;

  static const initial = StartupState(0, '正在载入图像引擎');
  static const connecting = StartupState(10, 'Connecting to native Halide/Metal');
  static const loadingFilms = StartupState(70, '正在载入原生胶片');
  static const ready = StartupState(100, 'Ready', done: true);
  static const failed = StartupState(100, '图像引擎不可用', done: true);
}
