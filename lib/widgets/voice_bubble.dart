import 'package:flutter/material.dart';

/// 微信样式语音气泡
class VoiceBubble extends StatelessWidget {
  final int duration; // 秒
  final bool isUser;
  final bool isPlaying;
  final VoidCallback? onTap;

  const VoiceBubble({
    super.key,
    required this.duration,
    required this.isUser,
    this.isPlaying = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 语音条宽度随时长变化，最小60，最大180
    final width = (60.0 + duration * 4).clamp(60.0, 180.0);
    final iconColor = isUser ? Colors.white : Colors.black87;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 播放/录音图标
            if (isUser)
              Icon(
                isPlaying ? Icons.stop : Icons.volume_up,
                size: 20,
                color: iconColor,
              )
            else
              Icon(
                isPlaying ? Icons.stop : Icons.play_arrow,
                size: 20,
                color: iconColor,
              ),
            const SizedBox(width: 6),
            // 时长
            Text(
              '${duration}"',
              style: TextStyle(
                fontSize: 14,
                color: iconColor,
              ),
            ),
            // 我方消息：声波动画在右侧
            if (isUser) ...[
              const Spacer(),
              _buildSoundWave(iconColor),
            ],
            // 对方消息：声波动画在左侧(图标和时长之间)
            if (!isUser) ...[
              const SizedBox(width: 8),
              _buildSoundWave(iconColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSoundWave(Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final heights = [6.0, 10.0, 14.0];
        return Container(
          width: 3,
          height: isPlaying ? heights[i] : heights[i] * 0.6,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: color.withOpacity(isPlaying ? 0.9 : 0.5),
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }
}
