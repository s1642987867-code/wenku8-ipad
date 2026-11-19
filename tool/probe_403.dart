import 'dart:io';

Future<void> main() async {
  // 打印 403 响应的完整关键信息（CF 挑战类型判断）
  final c = HttpClient();
  c.userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  final req =
      await c.getUrl(Uri.parse('https://dl.wenku8.com/down.php?type=txt&id=2334'));
  final resp = await req.close();
  print('status=${resp.statusCode}');
  resp.headers.forEach((k, v) => print('$k: $v'));
  final body = <int>[];
  await for (final chunk in resp) {
    body.addAll(chunk);
  }
  final s = String.fromCharCodes(body);
  // 查找挑战相关关键字
  for (final kw in ['challenge', 'turnstile', 'cf-chl', 'ray', 'error', 'blocked', 'attention']) {
    final i = s.toLowerCase().indexOf(kw);
    if (i >= 0) {
      print('\nKW[$kw]@${i}: ${s.substring((i - 80).clamp(0, s.length), (i + 200).clamp(0, s.length))}');
    }
  }
  c.close();
}
