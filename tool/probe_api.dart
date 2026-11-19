import 'dart:io';
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;
import 'package:wenku8_ipad/api/wenku8_api.dart';

http.Client makeClient() {
  final hc = HttpClient();
  hc.userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  return IOClient(hc);
}

Future<void> main() async {
  // 1. 包内 API
  final api = Wenku8Api();
  try {
    final text = await api.fetchBookText('2906');
    print('package API OK len=${text.length}');
    print(text.substring(0, 150));
  } catch (e) {
    print('package API ERR $e');
  }
  api.dispose();

  // 2. 原始 dart:io HttpClient
  final c = HttpClient();
  c.userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  try {
    final req = await c.getUrl(Uri.parse('https://dl.wenku8.com/down.php?type=txt&id=2906'));
    final resp = await req.close();
    print('raw dart:io status: ${resp.statusCode}');
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
    }
    print('raw len=${bytes.length}');
  } catch (e) {
    print('raw dart:io ERR $e');
  }
  c.close();

  // 3. IOClient 带 UA
  try {
    final cl = makeClient();
    final r = await cl.get(Uri.parse('https://dl.wenku8.com/down.php?type=txt&id=2906'));
    print('IOClient status: ${r.statusCode} len=${r.bodyBytes.length}');
    cl.close();
  } catch (e) {
    print('IOClient ERR $e');
  }
}
