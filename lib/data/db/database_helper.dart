import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../model/chat/chat_data_response_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('chat_database.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  whatsapp_message_id TEXT,
  reply_to TEXT,
  whatsapp_account_id TEXT,
  campaign_id TEXT,
  chatbot_id TEXT,
  template_id TEXT,
  conversation_id TEXT,
  message TEXT,
  type TEXT,
  message_type TEXT,
  media_id TEXT,
  media_url TEXT,
  media_type TEXT,
  mime_type TEXT,
  media_caption TEXT,
  media_path TEXT,
  local_media_path TEXT,
  media_filename TEXT,
  status TEXT,
  created_at TEXT,
  updated_at TEXT
)
''');
  }

  Future<void> insertMessage(MessagesData message) async {
    final db = await instance.database;
    final map = message.toMap();
    
    final existing = await db.query('messages', columns: ['local_media_path'], where: 'id = ?', whereArgs: [message.id]);
    if (existing.isNotEmpty && existing.first['local_media_path'] != null) {
      map['local_media_path'] = existing.first['local_media_path'];
    }
    
    await db.insert(
      'messages',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertMessagesList(List<MessagesData> messages) async {
    if (messages.isEmpty) return;
    final db = await instance.database;
    
    final ids = messages.map((e) => e.id).where((e) => e != null).toList();
    final localPaths = <String, String>{};
    
    if (ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      final existing = await db.query('messages', columns: ['id', 'local_media_path'], where: 'id IN ($placeholders)', whereArgs: ids);
      for (var row in existing) {
        if (row['local_media_path'] != null) {
          localPaths[row['id'].toString()] = row['local_media_path'].toString();
        }
      }
    }

    Batch batch = db.batch();
    for (var message in messages) {
      if (localPaths.containsKey(message.id)) {
        message.localMediaPath = localPaths[message.id];
      }
      final map = message.toMap();
      batch.insert(
        'messages',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<MessagesData>> getMessages(String conversationId, int limit, int offset) async {
    final db = await instance.database;
    final result = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );

    return result.map((json) => MessagesData.fromMap(json)).toList();
  }
  
  Future<MessagesData?> getLatestMessage(String conversationId) async {
    final db = await instance.database;
    final result = await db.query(
      'messages',
      where: 'conversation_id = ? AND id IS NOT NULL AND id != "" AND id NOT LIKE "temp_%"',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: 1,
    );

    if (result.isNotEmpty) {
      return MessagesData.fromMap(result.first);
    }
    return null;
  }

  Future<void> updateMessageStatusByWhatsappId(String whatsappMessageId, String newStatus) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'status': newStatus},
      where: 'whatsapp_message_id = ?',
      whereArgs: [whatsappMessageId],
    );
  }

  Future<void> updateMessageStatusById(String id, String newStatus, {String? newWhatsappMessageId}) async {
    final db = await instance.database;
    Map<String, dynamic> updateData = {'status': newStatus};
    if (newWhatsappMessageId != null) {
      updateData['whatsapp_message_id'] = newWhatsappMessageId;
    }
    
    await db.update(
      'messages',
      updateData,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateLocalMediaPath(String idOrMediaId, String localPath) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'local_media_path': localPath},
      where: 'id = ? OR whatsapp_message_id = ? OR media_id = ?',
      whereArgs: [idOrMediaId, idOrMediaId, idOrMediaId],
    );
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
