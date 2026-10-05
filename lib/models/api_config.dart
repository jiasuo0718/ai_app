/// API服务商类型
enum ApiProvider {
  doubao, // 豆包(火山引擎)
  openai, // OpenAI兼容
  deepseek, // DeepSeek
  qwen, // 通义千问
  custom, // 自定义
}

/// API配置模型
class ApiConfig {
  final String id;
  String name; // 配置名称(如"我的豆包")
  ApiProvider provider; // 服务商
  String baseUrl; // 接口地址
  String apiKey; // 密钥
  String model; // 模型名
  String? ttsBaseUrl; // TTS接口地址(独立)
  String? ttsApiKey; // TTS密钥
  String? ttsVoiceId; // 默认TTS音色
  bool isDefault; // 是否默认
  DateTime createdAt;

  ApiConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.ttsBaseUrl,
    this.ttsApiKey,
    this.ttsVoiceId,
    this.isDefault = false,
    required this.createdAt,
  });

  String get providerLabel {
    switch (provider) {
      case ApiProvider.doubao:
        return '豆包';
      case ApiProvider.openai:
        return 'OpenAI';
      case ApiProvider.deepseek:
        return 'DeepSeek';
      case ApiProvider.qwen:
        return '通义千问';
      case ApiProvider.custom:
        return '自定义';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider.index,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'ttsBaseUrl': ttsBaseUrl,
        'ttsApiKey': ttsApiKey,
        'ttsVoiceId': ttsVoiceId,
        'isDefault': isDefault,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ApiConfig.fromJson(Map<String, dynamic> json) => ApiConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        provider: ApiProvider.values[json['provider'] as int],
        baseUrl: json['baseUrl'] as String,
        apiKey: json['apiKey'] as String,
        model: json['model'] as String,
        ttsBaseUrl: json['ttsBaseUrl'] as String?,
        ttsApiKey: json['ttsApiKey'] as String?,
        ttsVoiceId: json['ttsVoiceId'] as String?,
        isDefault: json['isDefault'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// 用户设置
class UserSettings {
  String userName; // 用户昵称
  String userAvatar; // 用户头像
  String defaultApiConfigId; // 默认API配置ID
  bool autoPlayVoice; // 自动播放AI语音

  UserSettings({
    this.userName = '我',
    this.userAvatar = '',
    this.defaultApiConfigId = '',
    this.autoPlayVoice = true,
  });

  Map<String, dynamic> toJson() => {
        'userName': userName,
        'userAvatar': userAvatar,
        'defaultApiConfigId': defaultApiConfigId,
        'autoPlayVoice': autoPlayVoice,
      };

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
        userName: json['userName'] as String? ?? '我',
        userAvatar: json['userAvatar'] as String? ?? '',
        defaultApiConfigId: json['defaultApiConfigId'] as String? ?? '',
        autoPlayVoice: json['autoPlayVoice'] as bool? ?? true,
      );
}
