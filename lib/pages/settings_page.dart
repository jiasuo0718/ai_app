import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/api_config.dart';
import '../services/storage_service.dart';
import 'api_config_page.dart';

/// 设置页
class SettingsPage extends StatefulWidget {
  final StorageService storage;
  final UserSettings userSettings;

  const SettingsPage({
    super.key,
    required this.storage,
    required this.userSettings,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _nameCtrl;
  late String _avatar;
  late bool _autoPlayVoice;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.userSettings.userName);
    _avatar = widget.userSettings.userAvatar;
    _autoPlayVoice = widget.userSettings.autoPlayVoice;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final XFile? img = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
      );
      if (img != null) {
        setState(() => _avatar = img.path);
        _saveSettings();
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    final s = UserSettings(
      userName: _nameCtrl.text.trim().isEmpty ? '我' : _nameCtrl.text.trim(),
      userAvatar: _avatar,
      defaultApiConfigId: widget.userSettings.defaultApiConfigId,
      autoPlayVoice: _autoPlayVoice,
    );
    await widget.storage.saveUserSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDEDED),
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),
          // 个人信息
          _buildSection(
            children: [
              ListTile(
                leading: const Text('头像', style: TextStyle(fontSize: 16)),
                trailing: GestureDetector(
                  onTap: _pickAvatar,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: const Color(0xFF07C160),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _avatar.isNotEmpty
                        ? Image.file(File(_avatar), fit: BoxFit.cover)
                        : const Icon(Icons.person, color: Colors.white),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 14, endIndent: 14),
              ListTile(
                leading: const Text('昵称', style: TextStyle(fontSize: 16)),
                title: TextField(
                  controller: _nameCtrl,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '设置昵称',
                  ),
                  onSubmitted: (_) => _saveSettings(),
                ),
              ),
            ],
          ),
          // API配置
          _buildSection(
            children: [
              ListTile(
                leading: const Icon(Icons.api, color: Colors.black54),
                title: const Text('API配置'),
                subtitle: Text(
                  '${widget.storage.getApiConfigs().length} 个配置',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ApiConfigPage(storage: widget.storage),
                    ),
                  );
                },
              ),
            ],
          ),
          // 聊天设置
          _buildSection(
            title: '聊天设置',
            children: [
              SwitchListTile(
                title: const Text('自动播放AI语音'),
                subtitle: const Text('AI回复语音后自动播放'),
                value: _autoPlayVoice,
                activeColor: const Color(0xFF07C160),
                onChanged: (v) {
                  setState(() => _autoPlayVoice = v);
                  _saveSettings();
                },
              ),
            ],
          ),
          // 关于
          _buildSection(
            children: const [
              ListTile(
                leading: Icon(Icons.info_outline, color: Colors.black54),
                title: Text('关于'),
                subtitle: Text('AI聊天 v1.0.0',
                    style: TextStyle(fontSize: 12)),
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
}
