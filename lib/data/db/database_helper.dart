import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../model/chat/chat_data_response_model.dart';
import '../model/home/chat_list_response_model.dart';

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
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
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
    await _createConversationsTable(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createConversationsTable(db);
    }
  }

  Future _createConversationsTable(Database db) async {
    await db.execute('''
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  contact_id TEXT,
  status TEXT,
  last_message_at TEXT,
  created_at TEXT,
  updated_at TEXT,
  contact TEXT,
  last_message TEXT,
  unseen_messages TEXT
)
''');
    // Indexing for rapid inbox scrolling
    await db.execute('CREATE INDEX idx_conversations_created_at ON conversations (created_at DESC)');
    await db.execute('CREATE INDEX idx_messages_conversation_id ON messages (conversation_id)');
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

  Future<void> deleteMessage(String id) async {
    final db = await instance.database;
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMessagesByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await instance.database;
    // Create placeholders for the IN clause
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'messages',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<void> deleteConversationsByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    
    final batch = db.batch();
    // Delete the conversations
    batch.delete(
      'conversations',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    // Delete associated messages
    batch.delete(
      'messages',
      where: 'conversation_id IN ($placeholders)',
      whereArgs: ids,
    );
    
    await batch.commit(noResult: true);
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

  Future<void> insertConversationsList(List<ConversationData> conversationsList) async {
    final db = await instance.database;
    final batch = db.batch();

    for (var conversation in conversationsList) {
      if (conversation.id == null) continue;

      Map<String, dynamic> row = {
        'id': conversation.id,
        'user_id': conversation.userId,
        'contact_id': conversation.contactId,
        'status': conversation.status,
        'last_message_at': conversation.lastMessageAt,
        'created_at': conversation.createdAt,
        'updated_at': conversation.updatedAt,
        'contact': conversation.contact != null ? jsonEncode(conversation.contact!.toJson()) : null,
        'last_message': conversation.lastMessage != null ? jsonEncode(conversation.lastMessage!.toJson()) : null,
        'unseen_messages': conversation.unseenMessages,
      };

      batch.insert(
        'conversations',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ConversationData>> getConversations(int limit, int offset, {String? status}) async {
    final db = await instance.database;
    
    String whereClause = '1 = 1';
    List<dynamic> whereArgs = [];
    
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      whereClause += ' AND status = ?';
      // Normalize status mapping if needed. 'important' corresponds to status '1' typically, etc.
      String queryStatus = status;
      if (status.toLowerCase() == 'pending') queryStatus = '0';
      if (status.toLowerCase() == 'done') queryStatus = '1'; 
      // wait, the app might use different statuses. Let's just pass status as is and let the controller handle it if needed.
      whereArgs.add(queryStatus);
    }

    final result = await db.query(
      'conversations',
      where: whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'last_message_at DESC', // Sort by newest message
      limit: limit,
      offset: offset,
    );

    return result.map((row) {
      return ConversationData(
        id: row['id'] as String?,
        userId: row['user_id'] as String?,
        contactId: row['contact_id'] as String?,
        status: row['status'] as String?,
        lastMessageAt: row['last_message_at'] as String?,
        createdAt: row['created_at'] as String?,
        updatedAt: row['updated_at'] as String?,
        contact: row['contact'] != null ? Contact.fromJson(jsonDecode(row['contact'] as String)) : null,
        lastMessage: row['last_message'] != null ? LastMessage.fromJson(jsonDecode(row['last_message'] as String)) : null,
        unseenMessages: row['unseen_messages'] as String?,
      );
    }).toList();
  }

  Future<void> clearConversations() async {
    final db = await instance.database;
    await db.delete('conversations');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
