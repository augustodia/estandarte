import 'sound_native.dart' if (dart.library.js_interop) 'sound_web.dart' as impl;

abstract final class SoundPlayer {
  static bool enabled = true;

  static void unlock() => impl.unlockAudio();

  static void play(String name) {
    if (!enabled) return;
    impl.playSound(name);
  }
}
