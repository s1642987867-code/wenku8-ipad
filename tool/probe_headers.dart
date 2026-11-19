import 'dart:io';

Future<void> main() async {
  final variants = <int, Map<String, String>>{
    0: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
    },
    1: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
      'Accept': '*/*',
    },
    2: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Referer': 'https://wenku8.cc/',
    },
  };
  for (final e in variants.entries) {
    final c = HttpClient();
    try {
      final req =
          await c.getUrl(Uri.parse('https://dl.wenku8.com/down.php?type=txt&id=2334'));
      req.headers.add(HttpHeaders.acceptEncodingHeader, 'gzip');
      e.value.forEach((k, v) => req.headers.add(k, v));
      final resp = await req.close();
      print('variant ${e.key} status=${resp.statusCode}');
      final body = <int>[];
      await for (final chunk in resp) {
        body.addAll(chunk);
      }
      print('  len=${body.length} head=${String.fromCharCodes(body.take(60))}');
    } catch (err) {
      print('variant ${e.key} ERR $err');
    }
    c.close();
    await Future.delayed(const Duration(seconds: 5));
  }
}
