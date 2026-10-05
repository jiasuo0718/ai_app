/// 消息类型
enum MessageType { text, voice, image, system }

/// 聊天消息模型
class ChatMessage {
  final String id;
  final String conversationId;
  final bool isUser; // true=用户发送, false=AI回复
  final MessageType type;
  final String content; // 文字内容 或 语音文件路径 或 图片路径
  final int voiceDuration; // 语音时长(秒)
  final DateTime createdAt;
  final String? roleName; // AI角色名(用于显示)
  final String? roleAvatar; // AI角色头像

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.isUser,
    required this.type,
    required this.content,
    this.voiceDuration = 0,
    required this.createdAt,
    this.roleName,
    this.roleAvatar,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'isUser': isUser,
        'type': type.index,
        'content': content,
        'voiceDuration': voiceDuration,
        'createdAt': createdAt.toIso8601String(),
        'roleName': roleName,
        'roleAvatar': roleAvatar,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        isUser: json['isUser'] as bool,
        type: MessageType.values[json['type'] as int],
        content: json['content'] as String,
        voiceDuration: (json['voiceDuration'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        roleName: json['roleName'] as String?,
        roleAvatar: json['roleAvatar'] as String?,
      );
}
