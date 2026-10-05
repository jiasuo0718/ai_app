import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/api_config.dart';
import '../models/character.dart';
import '../models/chat_message.dart';

/// LLM大模型服务 - 支持多家API(OpenAI兼容格式)
class LlmService {
  final Dio _dio = Dio();

  /// 发送聊天请求，返回AI回复文字
  /// [apiConfig] API配置
  /// [character] 角色卡(提供systemPrompt)
  /// [history] 历史消息列表
  /// [userInput] 用户最新输入
  Future<String> chat({
    required ApiConfig apiConfig,
    required Character character,
    required List<ChatMessage> history,
    required String userInput,
  }) async {
    // 构建消息列表
    final List<Map<String, String>> messages = [];

    // 系统提示词
    if (character.systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': character.systemPrompt});
    }

    // 历史消息(最多保留20条，避免token超限)
    final recentHistory = history.length > 20
        ? history.sublist(history.length - 20)
        : history;
    for (final msg in recentHistory) {
      if (msg.type == MessageType.text) {
        messages.add({
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.content,
        });
      }
    }

    // 当前用户输入
    messages.add({'role': 'user', 'content': userInput});

    // 构建请求体(OpenAI兼容格式)
    final body = {
      'model': apiConfig.model,
      'messages': messages,
      'temperature': character.temperature,
      'max_tokens': character.maxTokens,
      'stream': false,
    };

    // 拼接完整URL
    String url = apiConfig.baseUrl;
    if (!url.endsWith('/chat/completions')) {
      url = url.endsWith('/')
          ? '${url}chat/completions'
          : '$url/chat/completions';
    }

    try {
      final response = await _dio.post(
        url,
        data: jsonEncode(body),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${apiConfig.apiKey}',
          },
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic> &&
            data['choices'] != null &&
            (data['choices'] as List).isNotEmpty) {
          final content = data['choices'][0]['message']['content'];
          return content?.toString().trim() ?? '（无回复内容）';
        }
      }
      return 'API返回异常: ${response.statusCode}';
    } on DioException catch (e) {
      if (e.response != null) {
        return '请求失败: ${e.response?.statusCode} - ${e.response?.data}';
      }
      return '网络错误: ${e.message}';
    } catch (e) {
      return '出错了: $e';
    }
  }

  /// 测试API连接是否正常
  Future<bool> testConnection(ApiConfig config) async {
    try {
      String url = config.baseUrl;
      if (!url.endsWith('/chat/completions')) {
        url = url.endsWith('/')
            ? '${url}chat/completions'
            : '$url/chat/completions';
      }
      final response = await _dio.post(
        url,
        data: jsonEncode({
          'model': config.model,
          'messages': [
            {'role': 'user', 'content': 'hi'}
          ],
          'max_tokens': 5,
        }),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
