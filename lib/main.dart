import 'package:flutter/material.dart';
import 'models/api_config.dart';
import 'services/storage_service.dart';
import 'pages/conversation_list_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();
  final settings = storage.getUserSettings();
  runApp(MyApp(storage: storage, userSettings: settings));
}

class MyApp extends StatelessWidget {
  final StorageService storage;
  final UserSettings userSettings;

  const MyApp({
    super.key,
    required this.storage,
    required this.userSettings,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI聊天',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        primaryColor: const Color(0xFF07C160),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEDEDED),
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
      ),
      home: ConversationListPage(
        storage: storage,
        userSettings: userSettings,
      ),
    );
  }
}
