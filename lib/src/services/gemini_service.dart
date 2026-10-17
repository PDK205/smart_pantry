import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Các model Gemini cho người dùng chọn trong Cài đặt.
class GeminiModel {
  final String id;
  final String label;
  final String description;
  const GeminiModel(this.id, this.label, this.description);
}

const kGeminiModels = [
  GeminiModel('gemini-3.5-flash-lite', 'Gemini 3.5 Flash-Lite', 'Nhanh & rẻ nhất'),
  GeminiModel('gemini-3.8-flash', 'Gemini 3.8 Flash', 'Cân bằng — khuyên dùng'),
  GeminiModel('gemini-4-argon', 'Gemini 4 Argon', 'Thông minh, nhận diện chính xác nhất'),
];
const kDefaultModel = 'gemini-3.8-flash';
const kDefaultBaseUrl = 'https://generativelanguage.googleapis.com';

class GeminiException implements Exception {
  GeminiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Đoán định dạng ảnh từ "magic bytes" — Gemini cần mimeType đúng.
String detectImageMediaType(Uint8List b) {
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return 'image/gif';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/jpeg';
}

/// Một part ảnh để gửi trong `contents`.
Map<String, dynamic> imagePart(Uint8List bytes) => {
      'inlineData': {
        'mimeType': detectImageMediaType(bytes),
        'data': base64Encode(bytes),
      },
    };

/// Một part văn bản.
Map<String, dynamic> textPart(String text) => {'text': text};

/// Ghép phần văn bản (bỏ qua phần "thought") của candidate đầu tiên.
String _candidateText(Map<String, dynamic> response) {
  final candidates = response['candidates'];
  if (candidates is! List || candidates.isEmpty) return '';
  final content = (candidates.first as Map)['content'];
  final parts = content is Map ? content['parts'] : null;
  if (parts is! List) return '';
  final b = StringBuffer();
  for (final p in parts) {
    if (p is Map && p['thought'] != true && p['text'] is String) b.write(p['text']);
  }
  return b.toString();
}

String? _finishReason(Map<String, dynamic> response) {
  final candidates = response['candidates'];
  if (candidates is! List || candidates.isEmpty) return null;
  return (candidates.first as Map)['finishReason'] as String?;
}

/// Ném lỗi thân thiện nếu yêu cầu/câu trả lời bị chặn vì an toàn.
void _checkBlocked(Map<String, dynamic> response) {
  final fb = response['promptFeedback'];
  if (fb is Map && fb['blockReason'] != null) {
    throw GeminiException('Yêu cầu bị Gemini từ chối (${fb['blockReason']}). Hãy thử nội dung/ảnh khác.');
  }
  final reason = _finishReason(response);
  if (reason == 'SAFETY' || reason == 'PROHIBITED_CONTENT' || reason == 'BLOCKLIST') {
    throw GeminiException('Câu trả lời bị chặn bởi bộ lọc an toàn của Gemini. Hãy thử lại.');
  }
}

/// Đọc JSON có cấu trúc từ phản hồi generateContent.
Map<String, dynamic> extractJson(Map<String, dynamic> response) {
  _checkBlocked(response);
  var text = _candidateText(response).trim();
  // Phòng khi model vẫn bọc JSON trong ```json ... ```.
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '').replaceFirst(RegExp(r'\s*```$'), '');
  }
  if (text.isNotEmpty) {
    try {
      final j = jsonDecode(text);
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
  }
  if (_finishReason(response) == 'MAX_TOKENS') {
    throw GeminiException('Câu trả lời của AI quá dài và bị cắt. Hãy thử lại.');
  }
  throw GeminiException('AI không trả về dữ liệu đúng định dạng. Hãy thử lại.');
}

/// Client gọi trực tiếp Gemini API (REST).
///
/// Lưu ý bảo mật: app gọi thẳng API bằng key người dùng tự nhập (phù hợp app
/// cá nhân/demo). Khi phát hành rộng rãi, hãy đặt một backend proxy giữ key và
/// trỏ [baseUrl] tới proxy đó.
class GeminiService {
  GeminiService({
    required this.apiKey,
    this.model = kDefaultModel,
    String baseUrl = kDefaultBaseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final String baseUrl;
  final http.Client _client;

  Uri _uri(String method, {bool sse = false}) =>
      Uri.parse('$baseUrl/v1beta/models/$model:$method${sse ? '?alt=sse' : ''}');

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'x-goog-api-key': apiKey,
      };

  static String _friendlyError(int status, String body) {
    String? apiMsg;
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) apiMsg = (j['error'] as Map)['message'] as String?;
    } catch (_) {}
    if (apiMsg != null && apiMsg.contains('API key not valid')) {
      return 'API key không hợp lệ. Kiểm tra lại trong Cài đặt.';
    }
    switch (status) {
      case 400:
        return 'Yêu cầu không hợp lệ${apiMsg == null ? '' : ': $apiMsg'}';
      case 401:
        return 'API key không hợp lệ. Kiểm tra lại trong Cài đặt.';
      case 403:
        return 'API key không có quyền dùng model này (hoặc chưa bật Gemini API).';
      case 404:
        return 'Không tìm thấy model. Hãy chọn model khác trong Cài đặt.';
      case 413:
        return 'Ảnh quá lớn, hãy chụp lại với độ phân giải thấp hơn.';
      case 429:
        return 'Bạn gửi quá nhiều yêu cầu hoặc hết hạn mức. Đợi một chút rồi thử lại.';
      case 503:
        return 'Gemini đang quá tải, vui lòng thử lại sau ít phút.';
      default:
        return 'Lỗi máy chủ ($status)${apiMsg == null ? '' : ': $apiMsg'}';
    }
  }

  static bool _retryable(int s) => s == 429 || s == 500 || s == 502 || s == 503 || s == 504;

  void _requireKey() {
    if (apiKey.trim().isEmpty) {
      throw GeminiException('Chưa có API key. Vào Cài đặt để nhập Gemini API key.');
    }
  }

  Map<String, dynamic> _body({
    required String system,
    required List<Map<String, dynamic>> contents,
    required int maxTokens,
    Map<String, dynamic>? schema,
  }) =>
      {
        'systemInstruction': {
          'parts': [textPart(system)]
        },
        'contents': contents,
        'generationConfig': {
          'maxOutputTokens': maxTokens,
          if (schema != null) ...{
            'responseMimeType': 'application/json',
            'responseSchema': schema,
          },
        },
      };

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 120)}) async {
    _requireKey();
    final payload = jsonEncode(body);
    var attempt = 0;
    while (true) {
      attempt++;
      http.Response res;
      try {
        res = await _client.post(_uri('generateContent'), headers: _headers, body: payload).timeout(timeout);
      } on TimeoutException {
        throw GeminiException('Hết thời gian chờ phản hồi. Kiểm tra mạng và thử lại.');
      } catch (e) {
        throw GeminiException('Không kết nối được tới Gemini. Kiểm tra mạng. ($e)');
      }
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
      if (_retryable(res.statusCode) && attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt * attempt));
        continue;
      }
      throw GeminiException(_friendlyError(res.statusCode, utf8.decode(res.bodyBytes)),
          statusCode: res.statusCode);
    }
  }

  /// Gọi Gemini và ÉP trả về JSON đúng [schema] (structured output).
  ///
  /// [maxTokens] đã gồm cả token "suy nghĩ" của các model thinking nên để rộng.
  Future<Map<String, dynamic>> generateJson({
    required String system,
    required List<Map<String, dynamic>> contents,
    required Map<String, dynamic> schema,
    int maxTokens = 16384,
  }) async {
    final res = await _post(_body(system: system, contents: contents, maxTokens: maxTokens, schema: schema));
    return extractJson(res);
  }

  /// Trả lời dạng văn bản, stream từng đoạn (mượt hơn khi chat).
  Stream<String> streamText({
    required String system,
    required List<Map<String, dynamic>> contents,
    int maxTokens = 8192,
  }) async* {
    _requireKey();
    final req = http.Request('POST', _uri('streamGenerateContent', sse: true))
      ..headers.addAll(_headers)
      ..body = jsonEncode(_body(system: system, contents: contents, maxTokens: maxTokens));

    http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw GeminiException('Hết thời gian chờ phản hồi. Kiểm tra mạng và thử lại.');
    } catch (e) {
      throw GeminiException('Không kết nối được tới Gemini. Kiểm tra mạng. ($e)');
    }
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      throw GeminiException(_friendlyError(res.statusCode, body), statusCode: res.statusCode);
    }

    final lines = res.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      Map<String, dynamic> evt;
      try {
        evt = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final err = evt['error'];
      if (err is Map) throw GeminiException('Gemini báo lỗi: ${err['message']}');
      final t = _candidateText(evt);
      if (t.isNotEmpty) yield t;
      _checkBlocked(evt);
    }
  }

  /// Kiểm tra key & model hoạt động (không tốn token).
  Future<void> ping() async {
    _requireKey();
    http.Response res;
    try {
      res = await _client
          .get(Uri.parse('$baseUrl/v1beta/models/$model'), headers: _headers)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw GeminiException('Hết thời gian chờ phản hồi. Kiểm tra mạng và thử lại.');
    } catch (e) {
      throw GeminiException('Không kết nối được tới Gemini. Kiểm tra mạng. ($e)');
    }
    if (res.statusCode != 200) {
      throw GeminiException(_friendlyError(res.statusCode, utf8.decode(res.bodyBytes)),
          statusCode: res.statusCode);
    }
  }
}
