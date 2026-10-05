import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/character.dart';
import '../models/conversation.dart';
import '../models/api_config.dart';
import '../services/storage_service.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../widgets/message_bubble.dart';

/// 微信样式聊天页面
class ChatPage extends StatefulWidget {
  final Conversation conversation;
  final Character character;
  final StorageService storage;
  final UserSettings userSettings;

  const ChatPage({
    super.key,
    required this.conversation,
    required this.character,
    required this.storage,
    required this.userSettings,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  final _uuid = const Uuid();

  final LlmService _llm = LlmService();
  final TtsService _tts = TtsService();

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isRecording = false;
  bool _showEmoji = false;
  String? _playingMsgId;

  static const List<String> _emojis = [
    '😀', '😁', '😂', '🤣', '😃', '😄', '😅', '😆',
    '😉', '😊', '😋', '😎', '😍', '😘', '🥰', '😗',
    '🤔', '😐', '😑', '😶', '🙄', '😏', '😣', '😥',
    '😮', '🤐', '😯', '😪', '😫', '🥱', '😴', '😌',
    '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '👏',
    '🙏', '💪', '❤️', '💔', '💕', '💖', '💗', '🔥',
  ];

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() => _playingMsgId = null);
    });
    // 监听输入变化，实时切换发送/录音按钮
    _inputCtrl.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _audioPlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final msgs = widget.storage.getMessages(widget.conversation.id);
    setState(() => _messages = msgs);
    // 如果没有消息，发送开场白
    if (msgs.isEmpty && widget.character.greeting.isNotEmpty) {
      await _sendGreeting();
    }
    _scrollToBottom();
  }

  Future<void> _sendGreeting() async {
    final msg = ChatMessage(
      id: _uuid.v4(),
      conversationId: widget.conversation.id,
      isUser: false,
      type: MessageType.text,
      content: widget.character.greeting,
      createdAt: DateTime.now(),
      roleName: widget.character.name,
      roleAvatar: widget.character.avatar,
    );
    await widget.storage.appendMessage(msg);
    setState(() => _messages.add(msg));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ========== 发送文字消息 ==========
  Future<void> _sendText() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isLoading) return;
    _inputCtrl.clear();
    setState(() => _showEmoji = false);
    await _sendMessage(text, MessageType.text);
  }

  Future<void> _sendMessage(String content, MessageType type,
      {int voiceDuration = 0}) async {
    // 添加用户消息
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      conversationId: widget.conversation.id,
      isUser: true,
      type: type,
      content: content,
      voiceDuration: voiceDuration,
      createdAt: DateTime.now(),
    );
    await widget.storage.appendMessage(userMsg);
    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    // 更新会话最后消息
    final updatedConv = Conversation(
      id: widget.conversation.id,
      title: widget.conversation.title,
      characterId: widget.conversation.characterId,
      characterName: widget.conversation.characterName,
      characterAvatar: widget.conversation.characterAvatar,
      lastMessage: type == MessageType.text ? content : '[语音]',
      lastMessageTime: DateTime.now(),
      createdAt: widget.conversation.createdAt,
      updatedAt: DateTime.now(),
    );
    await widget.storage.upsertConversation(updatedConv);

    // 获取API配置
    final apiConfig = widget.storage.getDefaultApiConfig();
    if (apiConfig == null) {
      _addSystemMessage('请先在设置中配置API密钥');
      setState(() => _isLoading = false);
      return;
    }

    // 调用LLM
    final reply = await _llm.chat(
      apiConfig: apiConfig,
      character: widget.character,
      history: _messages,
      userInput: type == MessageType.text ? content : '[语音消息]',
    );

    // 添加AI文字回复
    final aiMsg = ChatMessage(
      id: _uuid.v4(),
      conversationId: widget.conversation.id,
      isUser: false,
      type: MessageType.text,
      content: reply,
      createdAt: DateTime.now(),
      roleName: widget.character.name,
      roleAvatar: widget.character.avatar,
    );
    await widget.storage.appendMessage(aiMsg);
    setState(() {
      _messages.add(aiMsg);
      _isLoading = false;
    });
    _scrollToBottom();

    // 如果角色启用语音，调用TTS生成语音
    if (widget.character.enableVoice && reply.isNotEmpty) {
      _generateVoice(reply, apiConfig);
    }
  }

  Future<void> _generateVoice(String text, ApiConfig config) async {
    try {
      final path = await _tts.synthesize(
        apiConfig: config,
        text: text,
        voiceId: widget.character.ttsVoiceId,
      );
      if (path != null) {
        final voiceMsg = ChatMessage(
          id: _uuid.v4(),
          conversationId: widget.conversation.id,
          isUser: false,
          type: MessageType.voice,
          content: path,
          voiceDuration: 5, // TTS返回时长需要额外解析，先给默认值
          createdAt: DateTime.now(),
          roleName: widget.character.name,
          roleAvatar: widget.character.avatar,
        );
        await widget.storage.appendMessage(voiceMsg);
        setState(() => _messages.add(voiceMsg));
        _scrollToBottom();

        // 自动播放
        if (widget.userSettings.autoPlayVoice) {
          _playVoice(voiceMsg);
        }
      }
    } catch (_) {
      // TTS失败静默处理
    }
  }

  void _addSystemMessage(String text) {
    final msg = ChatMessage(
      id: _uuid.v4(),
      conversationId: widget.conversation.id,
      isUser: false,
      type: MessageType.system,
      content: text,
      createdAt: DateTime.now(),
    );
    setState(() => _messages.add(msg));
  }

  // ========== 语音播放 ==========
  Future<void> _playVoice(ChatMessage msg) async {
    if (_playingMsgId == msg.id) {
      await _audioPlayer.stop();
      setState(() => _playingMsgId = null);
      return;
    }
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(msg.content));
      setState(() => _playingMsgId = msg.id);
    } catch (_) {}
  }

  // ========== 录音 ==========
  Future<void> _startRecording() async {
    final hasPermission = await _requestMicPermission();
    if (!hasPermission) return;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/recording_${_uuid.v4()}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _isRecording = true;
      });
    } catch (_) {}
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        // 获取录音时长(简化处理)
        await _sendMessage(path, MessageType.voice, voiceDuration: 3);
      }
    } catch (_) {
      setState(() => _isRecording = false);
    }
  }

  Future<bool> _requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  // ========== 清空聊天 ==========
  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text('确定要清空当前会话的所有消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.storage.clearMessages(widget.conversation.id);
      setState(() => _messages = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED), // 微信聊天背景灰
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F7),
        foregroundColor: Colors.black87,
        elevation: 0.5,
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 角色头像
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.grey[300],
              ),
              clipBehavior: Clip.antiAlias,
              child: widget.character.avatar.isNotEmpty
                  ? Image.file(File(widget.character.avatar),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.smart_toy, color: Colors.white))
                  : const Icon(Icons.smart_toy, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text(
              widget.character.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'clear') _clearChat();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'clear', child: Text('清空聊天记录')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (ctx, idx) {
                  if (idx == _messages.length && _isLoading) {
                    return _buildTypingIndicator();
                  }
                  final msg = _messages[idx];
                  return MessageBubble(
                    message: msg,
                    userAvatar: widget.userSettings.userAvatar,
                    isPlaying: _playingMsgId == msg.id,
                    onVoiceTap: msg.type == MessageType.voice
                        ? () => _playVoice(msg)
                        : null,
                  );
                },
              ),
            ),
          ),
          // 表情面板
          if (_showEmoji) _buildEmojiPanel(),
          // 底部输入栏
          _buildInputBar(),
        ],
      ),
    );
  }

  // 正在输入指示器
  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: Colors.grey[300],
            ),
            child: const Icon(Icons.smart_toy, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // 表情面板
  Widget _buildEmojiPanel() {
    return Container(
      height: 200,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          childAspectRatio: 1,
        ),
        itemCount: _emojis.length,
        itemBuilder: (ctx, idx) {
          return InkWell(
            onTap: () {
              _inputCtrl.text += _emojis[idx];
            },
            child: Center(
              child: Text(_emojis[idx], style: const TextStyle(fontSize: 24)),
            ),
          );
        },
      ),
    );
  }

  // 底部输入栏
  Widget _buildInputBar() {
    return Container(
      color: const Color(0xFFF7F7F7),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 表情按钮
          IconButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              setState(() => _showEmoji = !_showEmoji);
            },
            icon: Icon(
              _showEmoji ? Icons.keyboard : Icons.sentiment_satisfied_alt,
              size: 28,
              color: Colors.black54,
            ),
          ),
          // 输入框
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 40, maxHeight: 120),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                controller: _inputCtrl,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                onTap: () => setState(() => _showEmoji = false),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 发送/录音按钮
          if (_inputCtrl.text.isNotEmpty)
            TextButton(
              onPressed: _sendText,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF07C160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('发送',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
            )
          else
            GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopRecording(),
              onLongPressCancel: () => _stopRecording(),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.grey[300] : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                alignment: Alignment.center,
                child: Text(
                  _isRecording ? '松开 发送' : '按住 说话',
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ),
            ),
          // 加号按钮
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.add_circle_outline,
                size: 28, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
