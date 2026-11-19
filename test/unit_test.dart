import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_ipad/models/models.dart';
import 'package:wenku8_ipad/src/gbk.dart';

void main() {
  test('GBK decode 基本汉字', () {
    // '轻小说文库' 的 GBK 字节
    final bytes = [
      0xC7, 0xE1, // 轻
      0xD0, 0xA1, // 小
      0xCB, 0xB5, // 说
      0xCE, 0xC4, // 文
      0xBF, 0xE2, // 库
    ];
    expect(decodeGbk(bytes), '轻小说文库');
  });

  test('GBK decode ASCII', () {
    expect(decodeGbk('abc123'.codeUnits), 'abc123');
  });

  test('GBK decode 非法字节替换', () {
    expect(decodeGbk([0xFF, 0xFF]), contains('\uFFFD'));
  });

  test('Book JSON round-trip', () {
    final b = Book(
      aid: '2906',
      title: '寒蝉鸣泣之时',
      author: '龙骑士07',
      coverUrl: 'https://img.wenku8.com/image/2/2906/2906s.jpg',
      catalogs: ['恐怖', '悬疑'],
    );
    final b2 = Book.decode(b.encode());
    expect(b2.aid, b.aid);
    expect(b2.title, b.title);
    expect(b2.catalogs, b.catalogs);
  });

  test('ReaderSettings JSON round-trip', () {
    const s = ReaderSettings(fontSize: 22, mode: ReaderMode.twoPage);
    final s2 = ReaderSettings.fromJson(s.toJson());
    expect(s2.fontSize, 22);
    expect(s2.mode, ReaderMode.twoPage);
  });

  test('smartDecode 嗅探 utf-8 meta', () {
    final bytes = '<html><head><meta charset="utf-8"><body>hello</body></html>'
        .codeUnits;
    expect(smartDecode(bytes), contains('hello'));
  });
}
