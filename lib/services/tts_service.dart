/// 在线听书：flutter_tts 驱动，逐段朗读、播放/暂停、语速调节、定时停止
library;

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  double _rate = 1.0;
  String _lang = 'zh-CN';

  double get rate => _rate;
  set rate(double v) {
    _rate = v.clamp(0.5, 3.0);
    if (_initialized) _tts.setSpeechRate((_rate - 0.5) * 1.2); // 0.0-3.0 映射
  }

  Future<void> _init() async {
    if (_initialized) return;
    await _tts.setLanguage(_lang);
    await _tts.setSpeechRate((_rate - 0.5) * 1.2);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _initialized = true;
  }

  Future<bool> isAvailable() async {
    try {
      await _init();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 朗读一段文本；返回 Future 在朗读结束时完成
  Future<void> speak(String text) async {
    await _init();
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return;
    await _tts.speak(clean);
  }

  /// 朗读段落列表，逐段回调（onSegmentDone(i)），用于滚动跟随
  Future<void> speakParagraphs(List<String> paragraphs, {void Function(int)? onSegment}) async {
    await _init();
    for (var i = 0; i < paragraphs.length; i++) {
      final p = paragraphs[i].trim();
      if (p.isEmpty) continue;
      // setCompletionHandler 只有一个，同步等待即可
      await _tts.setCompletionHandler(() {}); // no-op handler
      await _tts.speak(p);
      // awaitSpeakCompletion(true) 使 speak() 阻塞至读完
      onSegment?.call(i);
    }
  }

  Future<void> pause() async => _tts.pause();
  Future<void> stop() async => _tts.stop();

  Future<void> setAwaitCompletion(bool v) async {
    await _tts.awaitSpeakCompletion(v);
  }
}
