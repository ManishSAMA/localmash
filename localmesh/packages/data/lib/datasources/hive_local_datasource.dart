import 'package:hive_flutter/hive_flutter.dart';
import 'package:domain/domain.dart';
import '../models/hive_message_adapter.dart';
import '../models/hive_peer_adapter.dart';
import '../models/hive_identity_adapter.dart';
import '../models/hive_chat_room_adapter.dart';

class HiveLocalDataSource {
  HiveLocalDataSource._();

  static const String messagesBoxName = 'messages';
  static const String peersBoxName = 'peers';
  static const String identityBoxName = 'identity';
  static const String chatRoomsBoxName = 'chat_rooms';
  static const String _boxKeysBoxName = 'box_keys';
  static const String _identityKeyName = 'identity_encryption_key';

  static void registerAdapters() {
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(HiveMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(HivePeerAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(HiveIdentityAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(HiveChatRoomAdapter());
    }
  }

  static Future<void> initialize() async {
    await Hive.initFlutter();
    registerAdapters();
  }

  static Future<void> openAllBoxes({
    required List<int> identityEncryptionKey,
  }) async {
    final cipher = HiveAesCipher(identityEncryptionKey);
    await Hive.openBox<LocalMeshMessage>(messagesBoxName);
    await Hive.openBox<Peer>(peersBoxName);
    await Hive.openBox<LocalMeshIdentity>(
      identityBoxName,
      encryptionCipher: cipher,
    );
    await Hive.openBox<ChatRoom>(chatRoomsBoxName);
  }

  static Box<LocalMeshMessage> get messagesBox =>
      Hive.box<LocalMeshMessage>(messagesBoxName);

  static Box<Peer> get peersBox => Hive.box<Peer>(peersBoxName);

  static Box<LocalMeshIdentity> get identityBox =>
      Hive.box<LocalMeshIdentity>(identityBoxName);

  static Box<ChatRoom> get chatRoomsBox => Hive.box<ChatRoom>(chatRoomsBoxName);

  static Future<List<int>> getOrCreateBoxEncryptionKey() async {
    final keysBox = await Hive.openBox(_boxKeysBoxName);
    if (keysBox.containsKey(_identityKeyName)) {
      final stored = keysBox.get(_identityKeyName);
      return List<int>.from(stored as List);
    }
    final key = Hive.generateSecureKey();
    await keysBox.put(_identityKeyName, key);
    return key;
  }

  static Future<void> clearAll() async {
    await messagesBox.clear();
    await peersBox.clear();
    await identityBox.clear();
    await chatRoomsBox.clear();
  }
}
