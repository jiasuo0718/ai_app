/// 角色卡模型
class Character {
  final String id;
  String name; // 角色名称
  String avatar; // 头像路径或资源名
  String systemPrompt; // 系统提示词(角色设定)
  String greeting; // 开场白
  String description; // 角色简介
  String ttsVoiceId; // TTS音色ID
  double temperature; // 生成温度
  int maxTokens; // 最大生成长度
  bool enableVoice; // 是否启用语音回复
  DateTime createdAt;
  DateTime updatedAt;

  Character({
    required this.id,
    required this.name,
    this.avatar = '',
    this.systemPrompt = '',
    this.greeting = '你好呀~',
    this.description = '',
    this.ttsVoiceId = '',
    this.temperature = 0.7,
    this.maxTokens = 2048,
    this.enableVoice = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'systemPrompt': systemPrompt,
        'greeting': greeting,
        'description': description,
        'ttsVoiceId': ttsVoiceId,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'enableVoice': enableVoice,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Character.fromJson(Map<String, dynamic> json) => Character(
        id: json['id'] as String,
        name: json['name'] as String,
        avatar: json['avatar'] as String? ?? '',
        systemPrompt: json['systemPrompt'] as String? ?? '',
        greeting: json['greeting'] as String? ?? '你好呀~',
        description: json['description'] as String? ?? '',
        ttsVoiceId: json['ttsVoiceId'] as String? ?? '',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
        maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 2048,
        enableVoice: json['enableVoice'] as bool? ?? true,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Character copyWith({
    String? name,
    String? avatar,
    String? systemPrompt,
    String? greeting,
    String? description,
    String? ttsVoiceId,
    double? temperature,
    int? maxTokens,
    bool? enableVoice,
    DateTime? updatedAt,
  }) {
    return Character(
      id: id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      greeting: greeting ?? this.greeting,
      description: description ?? this.description,
      ttsVoiceId: ttsVoiceId ?? this.ttsVoiceId,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      enableVoice: enableVoice ?? this.enableVoice,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
