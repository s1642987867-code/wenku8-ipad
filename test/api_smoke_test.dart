import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_ipad/api/wenku8_api.dart';

void main() {
  test('全本 TXT 解析为卷章树（真实下载，冒烟）', () async {
    final api = Wenku8Api();
    final (book, volumes) = await api.bookDetail('2906'); // Unnamed Memory
    expect(book.title, contains('Unnamed Memory'));
    expect(volumes, isNotEmpty);
    expect(volumes.first.chapters, isNotEmpty);

    final first = volumes.first.chapters.first;
    final content = await api.chapterContent('2906', first.cid);
    expect(content, isNotEmpty);
    expect(content.length, greaterThan(200));

    // 第二卷首个章节应从不同位置切出
    if (volumes.length > 1 && volumes[1].chapters.isNotEmpty) {
      final second = await api.chapterContent('2906', volumes[1].chapters.first.cid);
      expect(second, isNot(equals(content)));
    }
    api.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
