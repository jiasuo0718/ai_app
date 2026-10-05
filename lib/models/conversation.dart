/// 会话模型
class Conversation {
  final String id;
  String title; // 会话标题
  final String characterId; // 绑定的角色ID
  String characterName; // 角色名(冗余,方便列表显示)
  String characterAvatar; // 角色头像(冗余)
  String lastMessage; // 最后一条消息预览
  DateTime lastMessageTime; // 最后消息时间
  int unreadCount; // 未读计数
  DateTime createdAt;
  DateTime updatedAt;

  Conversation({
    required this.id,
    required this.title,
    required this.characterId,
    required this.characterName,
    this.characterAvatar = '',
    this.lastMessage = '',
    required this.lastMessageTime,
    this.unreadCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'characterId': characterId,
        'characterName': characterName,
        'characterAvatar': characterAvatar,
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime.toIso8601String(),
        'unreadCount': unreadCount,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        characterId: json['characterId'] as String,
        characterName: json['characterName'] as String,
        characterAvatar: json['characterAvatar'] as String? ?? '',
        lastMessage: json['lastMessage'] as String? ?? '',
        lastMessageTime: DateTime.parse(json['lastMessageTime'] as String),
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
