// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// TTS browser (SpeechSynthesis) untuk instruksi Absensi Toko web.
void speakLiveness(String text, {String lang = 'id-ID'}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;
  final synth = html.window.speechSynthesis;
  if (synth == null) return;
  try {
    synth.cancel();
    final utterance = html.SpeechSynthesisUtterance(trimmed)
      ..lang = lang
      ..rate = 1.05
      ..pitch = 1.0
      ..volume = 1.0;
    synth.speak(utterance);
  } catch (_) {}
}

void stopLivenessSpeech() {
  try {
    html.window.speechSynthesis?.cancel();
  } catch (_) {}
}
