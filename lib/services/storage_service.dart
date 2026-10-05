import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/character.dart';
import '../models/conversation.dart';
import '../models/api_config.dart';

/// 本地存储服务 - 所有数据保存在手机本地
class StorageService {
  static const _keyCharacters = 'characters';
  static const _keyConversations = 'conversations';
  static const _keyMessages = 'messages_'; // + conversationId
  static const _keyApiConfigs = 'api_configs';
  static const _keyUserSettings = 'user_settings';

  late SharedPreferences _prefs;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  // ========== 角色卡 ==========
  List<Character> getCharacters() {
    final str = _prefs.getString(_keyCharacters);
    if (str == null || str.isEmpty) return [];
    final List<dynamic> list = jsonDecode(str);
    return list.map((e) => Character.fromJson(e)).toList();
  }

  Future<void> saveCharacters(List<Character> list) async {
    await _prefs.setString(
      _keyCharacters,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> upsertCharacter(Character character) async {
    final list = getCharacters();
    final idx = list.indexWhere((e) => e.id == character.id);
    if (idx >= 0) {
      list[idx] = character;
    } else {
      list.add(character);
    }
    await saveCharacters(list);
  }

  Future<void> deleteCharacter(String id) async {
    final list = getCharacters()..removeWhere((e) => e.id == id);
    await saveCharacters(list);
  }

  Character? getCharacterById(String id) {
    try {
      return getCharacters().firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  // ========== 会话 ==========
  List<Conversation> getConversations() {
    final str = _prefs.getString(_keyConversations);
    if (str == null || str.isEmpty) return [];
    final List<dynamic> list = jsonDecode(str);
    return list.map((e) => Conversation.fromJson(e)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> saveConversations(List<Conversation> list) async {
    await _prefs.setString(
      _keyConversations,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> upsertConversation(Conversation conv) async {
    final list = getConversations();
    final idx = list.indexWhere((e) => e.id == conv.id);
    if (idx >= 0) {
      list[idx] = conv;
    } else {
      list.add(conv);
    }
    await saveConversations(list);
  }

  Future<void> deleteConversation(String id) async {
    final list = getConversations()..removeWhere((e) => e.id == id);
    await saveConversations(list);
    // 同时删除该会话的消息
    await _prefs.remove(_keyMessages + id);
  }

  // ========== 消息 ==========
  List<ChatMessage> getMessages(String conversationId) {
    final str = _prefs.getString(_keyMessages + conversationId);
    if (str == null || str.isEmpty) return [];
    final List<dynamic> list = jsonDecode(str);
    return list.map((e) => ChatMessage.fromJson(e)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> saveMessages(String conversationId, List<ChatMessage> msgs) async {
    await _prefs.setString(
      _keyMessages + conversationId,
      jsonEncode(msgs.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> appendMessage(ChatMessage msg) async {
    final list = getMessages(msg.conversationId);
    list.add(msg);
    await saveMessages(msg.conversationId, list);
  }

  Future<void> clearMessages(String conversationId) async {
    await _prefs.remove(_keyMessages + conversationId);
  }

  // ========== API配置 ==========
  List<ApiConfig> getApiConfigs() {
    final str = _prefs.getString(_keyApiConfigs);
    if (str == null || str.isEmpty) return [];
    final List<dynamic> list = jsonDecode(str);
    return list.map((e) => ApiConfig.fromJson(e)).toList();
  }

  Future<void> saveApiConfigs(List<ApiConfig> list) async {
    await _prefs.setString(
      _keyApiConfigs,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> upsertApiConfig(ApiConfig config) async {
    final list = getApiConfigs();
    // 如果设为默认，取消其他默认
    if (config.isDefault) {
      for (var c in list) {
        c.isDefault = false;
      }
    }
    final idx = list.indexWhere((e) => e.id == config.id);
    if (idx >= 0) {
      list[idx] = config;
    } else {
      list.add(config);
    }
    await saveApiConfigs(list);
  }

  Future<void> deleteApiConfig(String id) async {
    final list = getApiConfigs()..removeWhere((e) => e.id == id);
    await saveApiConfigs(list);
  }

  ApiConfig? getDefaultApiConfig() {
    final list = getApiConfigs();
    try {
      return list.firstWhere((e) => e.isDefault);
    } catch (_) {
      return list.isNotEmpty ? list.first : null;
    }
  }

  ApiConfig? getApiConfigById(String id) {
    try {
      return getApiConfigs().firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  // ========== 用户设置 ==========
  UserSettings getUserSettings() {
    final str = _prefs.getString(_keyUserSettings);
    if (str == null || str.isEmpty) return UserSettings();
    return UserSettings.fromJson(jsonDecode(str));
  }

  Future<void> saveUserSettings(UserSettings settings) async {
    await _prefs.setString(_keyUserSettings, jsonEncode(settings.toJson()));
  }
}
