import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/core/api_client.dart';

void main() {
  test('HTTP errors remain HTTP errors instead of backend connectivity errors', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = request.uri.path.endsWith('/login') ? 401 : 500;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'detail': request.uri.path.endsWith('/login')
            ? 'Invalid email or password'
            : 'Server error for test'
      }));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

    await expectLater(
      api.request('/login', method: 'POST', body: {'email': 'dummy', 'password': 'dummy'}),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.message, 'message', 'Invalid email or password')),
    );
    await expectLater(
      api.request('/v3/state'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 500)
          .having((e) => e.message, 'message', 'Server error for test')),
    );
  });
}
