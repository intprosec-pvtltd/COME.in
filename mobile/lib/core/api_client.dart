import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
const apiBase = String.fromEnvironment('API_URL',
defaultValue: 'http://10.0.2.2:8000');
class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode,
  this.message);
  @override String toString() => message;
} class ApiClient {
  String? token;
  Future<Uint8List> download(String path) async {
    final uri = path.startsWith('/api/') ? Uri.parse('$apiBase$path') : Uri.parse('$apiBase/api$path');
    final response = await http.get(uri,
    headers: {
      if(token!=null)'Authorization':'Bearer $token'
    }).timeout(const Duration(seconds:30));
    if(response.statusCode>=400) throw ApiException(response.statusCode,
    'Attachment is unavailable or access was denied');
    return response.bodyBytes;
  } ApiClient({
    this.token
  });
  Future<dynamic> upload(String path,
  String filename,
  List<int> bytes,
  String mime) async {
    if (bytes.length > 10 * 1024 * 1024) throw const ApiException(413,
    'Maximum attachment size is 10 MB');
    final request = http.MultipartRequest('POST',
    Uri.parse('$apiBase/api$path'));
    if (token != null) request.headers[
      'Authorization'
    ] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file',
    bytes,
    filename: filename,
    contentType: _mediaType(mime)));
    final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 45)));
    final parsed = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode,
      '${parsed is Map ? parsed['detail'] ?? 'Upload failed' : 'Upload failed'}');
    } return parsed;
  } static MediaType _mediaType(String mime) {
    final parts = mime.split('/');
    return MediaType(parts[
      0
    ],
    parts.length > 1 ? parts[
      1
    ] : 'octet-stream');
  } Future<dynamic> request(String path,
  {
    String method = 'GET',
    Map<String,
    dynamic>? body
  }) async {
    final uri = Uri.parse('$apiBase/api$path');
    final req = http.Request(method,
    uri);
    req.headers[
      'Content-Type'
    ] = 'application/json';
    if (token != null) req.headers[
      'Authorization'
    ] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    try {
      final streamed = await req.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);
      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        data = {
          'detail': 'Unexpected server response'
        };
      } if (response.statusCode >= 400) {
        final detail = data is Map ? data[
          'detail'
        ] : null;
        throw ApiException(response.statusCode,
        detail is String ? detail : 'Request failed (${response.statusCode})');
      } return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(0,
      'Cannot reach PG server. Check backend and connection.');
    }
  }
} typedef AttachmentUpload = Future<dynamic> Function(String,
String,
List<int>,
String);
typedef ApiRequest = Future<dynamic> Function(String,
{
  String method,
  Map<String,
  dynamic>? body
});
