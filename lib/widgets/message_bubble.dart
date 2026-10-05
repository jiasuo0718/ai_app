import 'dart:io';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import 'voice_bubble.dart';

/// 微信样式消息气泡
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String userAvatar;
  final VoidCallback? onVoiceTap;
  final bool isPlaying;

  const MessageBubble({
    super.key,
    required this.message,
    this.userAvatar = '',
    this.onVoiceTap,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          // 对方消息：头像在左
          if (!isUser) ...[
            _buildAvatar(message.roleAvatar ?? '', isUser),
            const SizedBox(width: 8),
          ],
          // 气泡内容
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 角色名(仅AI消息显示)
                if (!isUser && (message.roleName ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, left: 4),
                    child: Text(
                      message.roleName!,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                // 气泡
                Container(
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF07C160) // 微信绿
                        : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isUser ? 8 : 2),
                      topRight: Radius.circular(isUser ? 2 : 8),
                      bottomLeft: const Radius.circular(8),
                      bottomRight: const Radius.circular(8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: _buildContent(),
                ),
                const SizedBox(height: 2),
                // 时间
                Padding(
                  padding: EdgeInsets.only(
                      left: isUser ? 0 : 4, right: isUser ? 4 : 0),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          // 我方消息：头像在右
          if (isUser) ...[
            const SizedBox(width: 8),
            _buildAvatar(userAvatar, isUser),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (message.type) {
      case MessageType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 16,
              color: message.isUser ? Colors.white : Colors.black87,
              height: 1.4,
            ),
          ),
        );
      case MessageType.voice:
        return VoiceBubble(
          duration: message.voiceDuration,
          isUser: message.isUser,
          isPlaying: isPlaying,
          onTap: onVoiceTap,
        );
      case MessageType.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            File(message.content),
            width: 150,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 150,
              height: 150,
              child: Icon(Icons.broken_image),
            ),
          ),
        );
      case MessageType.system:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            message.content,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        );
    }
  }

  Widget _buildAvatar(String avatarPath, bool isUser) {
    final hasFile = avatarPath.isNotEmpty &&
        (avatarPath.startsWith('/') || avatarPath.startsWith('file:'));
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: isUser ? const Color(0xFF07C160) : Colors.grey[300],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasFile
          ? Image.file(
              File(avatarPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                isUser ? Icons.person : Icons.smart_toy,
                color: Colors.white,
                size: 24,
              ),
            )
          : Icon(
              isUser ? Icons.person : Icons.smart_toy,
              color: Colors.white,
              size: 24,
            ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
