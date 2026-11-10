import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Compile-time endpoint. For a USB-connected physical device use
/// --dart-define=API_URL=http://127.0.0.1:8000 with adb reverse tcp:8000.
/// The default remains Android emulator-only for backward compatibility.
const apiBase = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({this.token, String? baseUrl}) : _baseUrl = baseUrl ?? apiBase;
  String? token;
  final String _baseUrl;

  Uri _uri(String path) => Uri.parse(
    '$_baseUrl${path.startsWith('/api/') ? path : '/api$path'}',
  );

  Map<String, String> get _headers => <String, String>{
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// Never turn an HTTP 401, 422 or 500 into a misleading connectivity error.
  /// Never include response bodies or credentials in connection diagnostics.
  static Never _connectionFailure(Object error) {
    if (error is TimeoutException) {
      throw const ApiException(0, 'PG server request timed out. Check the connection and retry.');
    }
    if (error is SocketException) {
      throw const ApiException(0, 'Cannot connect to PG server. For local testing, check the running backend and USB port forwarding.');
    }
    if (error is HandshakeException || error is TlsException) {
      throw const ApiException(0, 'Secure connection to PG server failed. Check the server certificate.');
    }
    if (error is http.ClientException) {
      throw const ApiException(0, 'Network request failed. Check the API address and Android network permissions.');
    }
    throw error;
  }

  static dynamic _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      if (response.statusCode >= 400) {
        throw ApiException(response.statusCode,
            'PG server returned HTTP ${response.statusCode}. Please retry or check backend logs.');
      }
      throw const ApiException(0, 'PG server returned an unexpected response format.');
    }
  }

  static void _requireSuccess(http.Response response, dynamic decoded) {
    if (response.statusCode < 400) return;
    final detail = decoded is Map ? decoded['detail'] : null;
    throw ApiException(response.statusCode,
        detail is String && detail.isNotEmpty
            ? detail
            : 'PG server returned HTTP ${response.statusCode}.');
  }

  Future<Uint8List> download(String path) async {
    try {
      final response = await http
          .get(_uri(path), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode >= 400) {
        throw ApiException(response.statusCode,
            'Attachment unavailable or access denied (HTTP ${response.statusCode}).');
      }
      return response.bodyBytes;
    } on ApiException {
      rethrow;
    } on TimeoutException catch (error) {
      _connectionFailure(error);
    } on SocketException catch (error) {
      _connectionFailure(error);
    } on HandshakeException catch (error) {
      _connectionFailure(error);
    } on http.ClientException catch (error) {
      _connectionFailure(error);
    }
  }

  Future<dynamic> upload(String path, String filename, List<int> bytes,
      String mime) async {
    if (bytes.length > 10 * 1024 * 1024) {
      throw const ApiException(413, 'Maximum attachment size is 10 MB');
    }
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(_headers);
    request.files.add(http.MultipartFile.fromBytes(
      'file', bytes, filename: filename, contentType: _mediaType(mime),
    ));
    try {
      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 45)),
      );
      final parsed = _decode(response);
      _requireSuccess(response, parsed);
      return parsed;
    } on ApiException {
      rethrow;
    } on TimeoutException catch (error) {
      _connectionFailure(error);
    } on SocketException catch (error) {
      _connectionFailure(error);
    } on HandshakeException catch (error) {
      _connectionFailure(error);
    } on http.ClientException catch (error) {
      _connectionFailure(error);
    }
  }

  static MediaType _mediaType(String mime) {
    final parts = mime.split('/');
    return MediaType(parts.first,
        parts.length > 1 ? parts[1] : 'octet-stream');
  }

  Future<dynamic> request(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final req = http.Request(method, _uri(path));
    req.headers.addAll(_headers);
    req.headers['Content-Type'] = 'application/json';
    if (body != null) req.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 90)),
      );
      final parsed = _decode(response);
      _requireSuccess(response, parsed);
      return parsed;
    } on ApiException {
      rethrow;
    } on TimeoutException catch (error) {
      _connectionFailure(error);
    } on SocketException catch (error) {
      _connectionFailure(error);
    } on HandshakeException catch (error) {
      _connectionFailure(error);
    } on http.ClientException catch (error) {
      _connectionFailure(error);
    }
  }
}

typedef AttachmentUpload = Future<dynamic> Function(
    String, String, List<int>, String);
typedef ApiRequest = Future<dynamic> Function(String,
    {String method, Map<String, dynamic>? body});
