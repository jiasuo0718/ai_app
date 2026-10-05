import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/character.dart';
import '../models/conversation.dart';
import '../models/api_config.dart';
import '../services/storage_service.dart';
import 'chat_page.dart';
import 'character_list_page.dart';
import 'settings_page.dart';

/// 会话列表页（仿微信聊天列表）
class ConversationListPage extends StatefulWidget {
  final StorageService storage;
  final UserSettings userSettings;

  const ConversationListPage({
    super.key,
    required this.storage,
    required this.userSettings,
  });

  @override
  State<ConversationListPage> createState() => _ConversationListPageState();
}

class _ConversationListPageState extends State<ConversationListPage> {
  List<Conversation> _conversations = [];
  List<Character> _characters = [];
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _conversations = widget.storage.getConversations();
      _characters = widget.storage.getCharacters();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDEDED),
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('聊天',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateMenu,
          ),
        ],
      ),
      body: _conversations.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              itemCount: _conversations.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 72,
                color: Colors.grey[200],
              ),
              itemBuilder: (ctx, idx) {
                final conv = _conversations[idx];
                return _buildConversationItem(conv);
              },
            ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('还没有会话', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          Text('点击右上角 + 创建新会话',
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildConversationItem(Conversation conv) {
    return InkWell(
      onTap: () => _openConversation(conv),
      onLongPress: () => _showConversationMenu(conv),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // 头像
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: Colors.grey[300],
              ),
              clipBehavior: Clip.antiAlias,
              child: conv.characterAvatar.isNotEmpty
                  ? Image.file(File(conv.characterAvatar),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.smart_toy, color: Colors.white))
                  : const Icon(Icons.smart_toy, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.characterName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(conv.lastMessageTime),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    conv.lastMessage.isEmpty ? '开始聊天吧~' : conv.lastMessage,
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 未读角标
            if (conv.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${conv.unreadCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: 0,
      onTap: (idx) {
        if (idx == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CharacterListPage(
                storage: widget.storage,
                userSettings: widget.userSettings,
              ),
            ),
          ).then((_) => _loadData());
        } else if (idx == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsPage(
                storage: widget.storage,
                userSettings: widget.userSettings,
              ),
            ),
          ).then((_) => _loadData());
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.chat), label: '聊天'),
        BottomNavigationBarItem(
            icon: Icon(Icons.people_alt_outlined), label: '角色'),
        BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined), label: '设置'),
      ],
      selectedItemColor: const Color(0xFF07C160),
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
    );
  }

  // 创建菜单
  void _showCreateMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_comment),
              title: const Text('新建会话'),
              onTap: () {
                Navigator.pop(ctx);
                _createConversation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('管理角色'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CharacterListPage(
                      storage: widget.storage,
                      userSettings: widget.userSettings,
                    ),
                  ),
                ).then((_) => _loadData());
              },
            ),
          ],
        ),
      ),
    );
  }

  // 创建新会话
  Future<void> _createConversation() async {
    if (_characters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建角色卡')),
      );
      return;
    }
    // 如果只有一个角色，直接创建；多个则让用户选择
    Character? selected;
    if (_characters.length == 1) {
      selected = _characters.first;
    } else {
      selected = await showDialog<Character>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择角色'),
          children: _characters
              .map((c) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, c),
                    child: Text(c.name),
                  ))
              .toList(),
        ),
      );
    }
    if (selected == null) return;

    final now = DateTime.now();
    final conv = Conversation(
      id: _uuid.v4(),
      title: selected.name,
      characterId: selected.id,
      characterName: selected.name,
      characterAvatar: selected.avatar,
      lastMessage: '',
      lastMessageTime: now,
      createdAt: now,
      updatedAt: now,
    );
    await widget.storage.upsertConversation(conv);
    _loadData();
    _openConversation(conv);
  }

  void _openConversation(Conversation conv) {
    final character = widget.storage.getCharacterById(conv.characterId);
    if (character == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('角色不存在，可能已被删除')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          conversation: conv,
          character: character,
          storage: widget.storage,
          userSettings: widget.userSettings,
        ),
      ),
    ).then((_) => _loadData());
  }

  void _showConversationMenu(Conversation conv) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除会话', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                await widget.storage.deleteConversation(conv.id);
                _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (now.difference(dt).inDays == 1) {
      return '昨天';
    } else {
      return '${dt.month}/${dt.day}';
    }
  }
}
