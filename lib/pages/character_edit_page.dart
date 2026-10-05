import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/character.dart';
import '../services/storage_service.dart';

/// 角色卡编辑页
class CharacterEditPage extends StatefulWidget {
  final Character character;
  final StorageService storage;

  const CharacterEditPage({
    super.key,
    required this.character,
    required this.storage,
  });

  @override
  State<CharacterEditPage> createState() => _CharacterEditPageState();
}

class _CharacterEditPageState extends State<CharacterEditPage> {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _promptCtrl;
  late TextEditingController _greetingCtrl;
  late TextEditingController _voiceCtrl;
  late double _temperature;
  late int _maxTokens;
  late bool _enableVoice;
  late String _avatar;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final c = widget.character;
    _nameCtrl = TextEditingController(text: c.name);
    _descCtrl = TextEditingController(text: c.description);
    _promptCtrl = TextEditingController(text: c.systemPrompt);
    _greetingCtrl = TextEditingController(text: c.greeting);
    _voiceCtrl = TextEditingController(text: c.ttsVoiceId);
    _temperature = c.temperature;
    _maxTokens = c.maxTokens;
    _enableVoice = c.enableVoice;
    _avatar = c.avatar;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _promptCtrl.dispose();
    _greetingCtrl.dispose();
    _voiceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final XFile? img = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (img != null) {
        setState(() => _avatar = img.path);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写角色名称')),
      );
      return;
    }
    final updated = widget.character.copyWith(
      name: _nameCtrl.text.trim(),
      avatar: _avatar,
      description: _descCtrl.text.trim(),
      systemPrompt: _promptCtrl.text.trim(),
      greeting: _greetingCtrl.text.trim(),
      ttsVoiceId: _voiceCtrl.text.trim(),
      temperature: _temperature,
      maxTokens: _maxTokens,
      enableVoice: _enableVoice,
    );
    await widget.storage.upsertCharacter(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDEDED),
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('编辑角色'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存',
                style: TextStyle(
                    color: Color(0xFF07C160),
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),
          // 头像
          _buildSection(
            children: [
              ListTile(
                leading: const Text('头像', style: TextStyle(fontSize: 16)),
                trailing: GestureDetector(
                  onTap: _pickAvatar,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: Colors.grey[300],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _avatar.isNotEmpty
                        ? Image.file(File(_avatar), fit: BoxFit.cover)
                        : const Icon(Icons.smart_toy, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          // 基本信息
          _buildSection(
            children: [
              _buildTextField('名称', _nameCtrl),
              _buildDivider(),
              _buildTextField('简介', _descCtrl, maxLines: 2),
            ],
          ),
          // 角色设定
          _buildSection(
            title: '角色设定',
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('系统提示词（人设）',
                        style: TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _promptCtrl,
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: '例如：你是一个温柔体贴的女生，说话喜欢用~结尾...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
              _buildDivider(),
              _buildTextField('开场白', _greetingCtrl),
            ],
          ),
          // 语音设置
          _buildSection(
            title: '语音设置',
            children: [
              SwitchListTile(
                title: const Text('启用语音回复'),
                subtitle: const Text('AI回复时自动生成语音'),
                value: _enableVoice,
                activeColor: const Color(0xFF07C160),
                onChanged: (v) => setState(() => _enableVoice = v),
              ),
              if (_enableVoice) ...[
                _buildDivider(),
                _buildTextField('TTS音色ID', _voiceCtrl,
                    hint: '如 zh_female_qingxin'),
              ],
            ],
          ),
          // 生成参数
          _buildSection(
            title: '生成参数',
            children: [
              ListTile(
                title: const Text('温度'),
                subtitle: Slider(
                  value: _temperature,
                  min: 0,
                  max: 2,
                  divisions: 20,
                  activeColor: const Color(0xFF07C160),
                  label: _temperature.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _temperature = v),
                ),
                trailing: Text(_temperature.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 14)),
              ),
              _buildDivider(),
              ListTile(
                title: const Text('最大生成长度'),
                subtitle: Slider(
                  value: _maxTokens.toDouble(),
                  min: 256,
                  max: 8192,
                  divisions: 31,
                  activeColor: const Color(0xFF07C160),
                  label: '$_maxTokens',
                  onChanged: (v) => setState(() => _maxTokens = v.toInt()),
                ),
                trailing: Text('$_maxTokens',
                    style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection({String? title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text(title,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl,
      {int maxLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment:
            maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 16))),
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: maxLines,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => Divider(
      height: 1, indent: 14, endIndent: 14, color: Colors.grey[200]);
}
