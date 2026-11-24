/// GBK → String 解码器
/// wenku8.net 所有页面均为 GBK 编码。
/// 映射表从 assets/gbk_map.bin 加载（47880 字节，23940 个 uint16）。
library;

import 'dart:typed_data';
import 'dart:convert';

/// 预加载的 GBK 映射表
Uint16List? _gbkMap;

/// 初始化 GBK 映射表
/// [bytes] 是 assets/gbk_map.bin 的原始字节（47880 字节）
void initGbkMap(Uint8List bytes) {
  _gbkMap = bytes.buffer.asUint16List();
}

/// 是否已初始化
bool get gbkReady => _gbkMap != null;

/// GBK 字节流 → String
String decodeGbk(List<int> bytes) {
  final map = _gbkMap;
  if (map == null) {
    // 回退到 latin1（ASCII 正确，中文乱码但不崩溃）
    return latin1.decode(bytes);
  }
  final sb = StringBuffer();
  int i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b < 0x80) {
      sb.writeCharCode(b);
      i++;
    } else if (b >= 0x81 && b <= 0xFE && i + 1 < bytes.length) {
      final b2 = bytes[i + 1];
      if (b2 >= 0x40 && b2 <= 0xFE && b2 != 0x7F) {
        final hi = b - 0x81;
        final lo = b2 > 0x7F ? b2 - 0x41 : b2 - 0x40;
        final idx = hi * 190 + lo;
        if (idx < map.length) {
          final code = map[idx];
          if (code > 0) sb.writeCharCode(code);
        }
        i += 2;
      } else {
        i++;
      }
    } else {
      i++;
    }
  }
  return sb.toString();
}
