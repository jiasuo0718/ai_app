import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/character.dart';
import '../models/api_config.dart';
import '../services/storage_service.dart';
import 'character_edit_page.dart';

/// 角色卡管理页
class CharacterListPage extends StatefulWidget {
  final StorageService storage;
  final UserSettings userSettings;

  const CharacterListPage({
    super.key,
    required this.storage,
    required this.userSettings,
  });

  @override
  State<CharacterListPage> createState() => _CharacterListPageState();
}

class _CharacterListPageState extends State<CharacterListPage> {
  List<Character> _characters = [];
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _characters = widget.storage.getCharacters());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDEDED),
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('角色',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createCharacter,
          ),
        ],
      ),
      body: _characters.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _characters.length,
              itemBuilder: (ctx, idx) => _buildCard(_characters[idx]),
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('还没有角色卡', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          Text('点击右上角 + 创建你的第一个角色',
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildCard(Character c) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _editCharacter(c),
        onLongPress: () => _showMenu(c),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 头像
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[300],
                ),
                clipBehavior: Clip.antiAlias,
                child: c.avatar.isNotEmpty
                    ? Image.file(File(c.avatar),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.smart_toy, color: Colors.white))
                    : const Icon(Icons.smart_toy,
                        color: Colors.white, size: 32),
              ),
              const SizedBox(width: 14),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(c.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        if (c.enableVoice)
                          const Icon(Icons.volume_up,
                              size: 14, color: Colors.green),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.description.isEmpty ? '暂无简介' : c.description,
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '温度: ${c.temperature} | 最大Token: ${c.maxTokens}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createCharacter() async {
    final now = DateTime.now();
    final c = Character(
      id: _uuid.v4(),
      name: '新角色',
      createdAt: now,
      updatedAt: now,
    );
    await widget.storage.upsertCharacter(c);
    _loadData();
    _editCharacter(c);
  }

  void _editCharacter(Character c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterEditPage(
          character: c,
          storage: widget.storage,
        ),
      ),
    ).then((_) => _loadData());
  }

  void _showMenu(Character c) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制角色'),
              onTap: () async {
                Navigator.pop(ctx);
                final now = DateTime.now();
                final copy = Character(
                  id: _uuid.v4(),
                  name: '${c.name} 副本',
                  avatar: c.avatar,
                  systemPrompt: c.systemPrompt,
                  greeting: c.greeting,
                  description: c.description,
                  ttsVoiceId: c.ttsVoiceId,
                  temperature: c.temperature,
                  maxTokens: c.maxTokens,
                  enableVoice: c.enableVoice,
                  createdAt: now,
                  updatedAt: now,
                );
                await widget.storage.upsertCharacter(copy);
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  const Text('删除角色', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('删除角色'),
                    content: Text('确定删除「${c.name}」吗？相关会话不会被删除。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('取消')),
                      TextButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('删除',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await widget.storage.deleteCharacter(c.id);
                  _loadData();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
