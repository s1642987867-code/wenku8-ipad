/// GBK 解码器（纯 Dart）。映射表来自 lib/src/gbk_map.json（构建期由 Python 以
/// Python 标准库 `bytes.decode('gbk')` 生成，覆盖全部 21791 个有效双字节码位）。
library;

import 'dart:convert';

import 'gbk_map.dart' as m;

final Map<String, int> _map = m.gbkMap;

/// 将 GBK 字节解码为 Unicode 字符串。非法字节替换为 U+FFFD。
String decodeGbk(List<int> bytes) {
  final out = StringBuffer();
  var i = 0;
  final n = bytes.length;
  while (i < n) {
    final b = bytes[i];
    if (b < 0x80) {
      out.writeCharCode(b);
      i++;
      continue;
    }
    if (i + 1 < n) {
      final key =
          ((b < 16 ? '0' : '') + b.toRadixString(16) +
                  ((bytes[i + 1] < 16 ? '0' : '') +
                      bytes[i + 1].toRadixString(16)))
              .toUpperCase();
      final cp = _map[key];
      if (cp != null) {
        out.writeCharCode(cp);
        i += 2;
        continue;
      }
    }
    out.writeCharCode(0xFFFD);
    i++;
  }
  return out.toString();
}

/// 便捷扩展：bytes -> GBK 字符串。
extension GbkBytesExt on List<int> {
  String get gbkDecoded => decodeGbk(this);
}

/// 常见 HTML 实体解码（正文里出现 &amp; &lt; 等）。
String decodeHtmlEntities(String s) {
  return s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
}

/// 把 Dart 字符串按 UTF-8 编码后取 GBK 字节（用于登录等需要 POST GBK 参数的场合：
/// wenku8 的 app 接口参数为 UTF-8，站点网页接口参数需 GBK，这里提供 GBK 编码表反查）。
List<int> encodeGbk(String s) {
  final reverse = _reverseMap();
  final out = <int>[];
  for (final rune in s.runes) {
    final cp = rune & 0xFFFF;
    if (rune < 0x80) {
      out.add(rune);
    } else {
      final key = reverse[cp];
      if (key != null) {
        out.add(int.parse(key.substring(0, 2), radix: 16));
        out.add(int.parse(key.substring(2, 4), radix: 16));
      } else {
        out.add(0x3F); // '?'
      }
    }
  }
  return out;
}

Map<int, String>? _rev;
Map<int, String> _reverseMap() {
  return _rev ??= _map.map((k, v) => MapEntry(v, k));
}

final _charsetRegex = RegExp('charset=["\u0027]?([\\w-]+)', caseSensitive: false);

/// 智能解码 HTTP 响应体：优先按 HTTP 头/HTML meta 声明的 charset，
/// 否则启发式探测 GBK / UTF-8。
String smartDecode(List<int> bytes, {String? headerCharset}) {
  String? cs = headerCharset?.toLowerCase();
  if (cs == null || cs.isEmpty) {
    final head = utf8.decode(bytes.take(2048).toList(), allowMalformed: true);
    final m2 = _charsetRegex.firstMatch(head);
    cs = m2?.group(1)?.toLowerCase();
  }
  if (cs == 'gbk' || cs == 'gb2312' || cs == 'gb18030') {
    return decodeGbk(bytes);
  }
  if (cs == 'utf-8' || cs == 'utf8') {
    return utf8.decode(bytes, allowMalformed: true);
  }
  // 启发式：尝试严格 UTF-8，失败则按 GBK。
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return decodeGbk(bytes);
  }
}
