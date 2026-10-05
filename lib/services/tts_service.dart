import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/api_config.dart';

/// TTS语音合成服务 - 支持豆包TTS及OpenAI兼容TTS
class TtsService {
  final Dio _dio = Dio();
  final _uuid = const Uuid();

  /// 将文字合成为语音，返回本地音频文件路径
  /// [apiConfig] API配置(含TTS地址和密钥)
  /// [text] 要合成的文字
  /// [voiceId] 音色ID(优先使用角色卡的音色)
  Future<String?> synthesize({
    required ApiConfig apiConfig,
    required String text,
    String? voiceId,
  }) async {
    if (text.trim().isEmpty) return null;

    // 优先使用角色音色，其次用API配置默认音色
    final voice = voiceId?.isNotEmpty == true
        ? voiceId!
        : (apiConfig.ttsVoiceId ?? 'zh_female_qingxin');

    try {
      // 根据服务商选择不同TTS接口
      switch (apiConfig.provider) {
        case ApiProvider.doubao:
          return await _doubaoTts(apiConfig, text, voice);
        case ApiProvider.openai:
        case ApiProvider.deepseek:
        case ApiProvider.qwen:
        case ApiProvider.custom:
          return await _openAiCompatibleTts(apiConfig, text, voice);
      }
    } catch (e) {
      return null;
    }
  }

  /// 豆包(火山引擎)TTS
  Future<String?> _doubaoTts(ApiConfig config, String text, String voice) async {
    final ttsUrl = config.ttsBaseUrl ??
        'https://openspeech.bytedance.com/api/v1/tts';
    final ttsKey = config.ttsApiKey ?? config.apiKey;

    final body = {
      'app': {
        'appid': '',
        'token': ttsKey,
        'cluster': 'volcano_tts',
      },
      'user': {'uid': 'ai_chat_app_user'},
      'audio': {
        'voice_type': voice,
        'encoding': 'mp3',
        'speed_ratio': 1.0,
        'volume_ratio': 1.0,
        'pitch_ratio': 1.0,
      },
      'request': {
        'reqid': _uuid.v4(),
        'text': text,
        'text_type': 'plain',
        'operation': 'query',
        'with_frontend': 1,
        'frontend_type': 'unitTson',
      },
    };

    final response = await _dio.post(
      ttsUrl,
      data: jsonEncode(body),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer;$ttsKey',
        },
        responseType: ResponseType.json,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    if (response.statusCode == 200) {
      final data = response.data;
      if (data is Map && data['data'] != null) {
        final base64Audio = data['data'] as String;
        return await _saveBase64Audio(base64Audio);
      }
    }
    return null;
  }

  /// OpenAI兼容TTS接口
  Future<String?> _openAiCompatibleTts(
      ApiConfig config, String text, String voice) async {
    final ttsUrl = config.ttsBaseUrl ??
        (config.baseUrl.endsWith('/')
            ? '${config.baseUrl}audio/speech'
            : '${config.baseUrl}/audio/speech');
    final ttsKey = config.ttsApiKey ?? config.apiKey;

    final response = await _dio.post(
      ttsUrl,
      data: jsonEncode({
        'model': 'tts-1',
        'input': text,
        'voice': voice,
        'response_format': 'mp3',
      }),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $ttsKey',
        },
        responseType: ResponseType.bytes,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    if (response.statusCode == 200) {
      return await _saveBytesAudio(response.data as List<int>);
    }
    return null;
  }

  /// 保存base64音频到本地
  Future<String> _saveBase64Audio(String base64Str) async {
    final bytes = base64Decode(base64Str);
    return _saveBytesAudio(bytes);
  }

  /// 保存字节音频到本地
  Future<String> _saveBytesAudio(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final fileName = 'tts_${_uuid.v4()}.mp3';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
