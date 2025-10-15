import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:LangBridge/services/chat_socket_service.dart';
import 'package:LangBridge/models/chat.dart';
import 'package:LangBridge/models/message.dart';
import 'package:LangBridge/models/transcription_data.dart';
import 'package:LangBridge/services/api_service.dart';

const String appChatFixedId = "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a10";

class ChatRepository {
  final _uuid = const Uuid();
  final ChatSocketService chatSocketService = ChatSocketService();
  final ApiService _apiService = ApiService();

  final ValueNotifier<List<Chat>> _chatsNotifier = ValueNotifier<List<Chat>>([]);
  ValueNotifier<List<Chat>> get chatsStream => _chatsNotifier;

  Future<void> fetchChats() async {
    final chatDataList = await _apiService.getAllChats();
    if (chatDataList != null) {
      final chats = chatDataList.map((data) => Chat.fromJson(data)).toList();
      _chatsNotifier.value = chats;
    } else {
      _chatsNotifier.value = [];
    }
  }

  Future<Chat?> getOrCreatePrivateChat(String partnerId) async {
    final chatData = await _apiService.getOrCreatePrivateChat(partnerId);
    if (chatData != null) {
      return Chat.fromJson(chatData);
    }
    return null;
  }

  Future<Chat?> createNewChat(String title) async {
    final chatData = await _apiService.getOrCreatePrivateChat(title);
    if (chatData != null) {
      final newChat = Chat.fromJson(chatData);
      final currentChats = List<Chat>.from(_chatsNotifier.value);
      currentChats.add(newChat);
      _chatsNotifier.value = currentChats;
      return newChat;
    }
    return null;
  }

  Future<void> markChatAsRead(String chatId) async {
    await _apiService.markChatAsRead(chatId);
    final currentChats = List<Chat>.from(_chatsNotifier.value);
    final chatIndex = currentChats.indexWhere((c) => c.id == chatId);
    if (chatIndex != -1) {
      final oldChat = currentChats[chatIndex];
      currentChats[chatIndex] = Chat(
        id: oldChat.id,
        title: oldChat.title,
        createdAt: oldChat.createdAt,
        participants: oldChat.participants,
        lastMessage: oldChat.lastMessage,
        unreadCount: 0,
      );
      _chatsNotifier.value = currentChats;
    }
  }

  Future<void> connectToChat(Chat chat) async {
    List<Message> initialMessages = [];
    final messagesData = await _apiService.getChatMessages(chat.id);
    if (messagesData != null) {
      try {
        initialMessages = messagesData.map((data) => Message.fromJson(data)).toList();
      } catch (e) {
        print("Error parsing messages for chat ${chat.id}: $e");
      }
    }
    await chatSocketService.connect(chat.id, initialMessages);
  }

  void sendChatMessage({
    required String sender,
    required String content,
    MessageType type = MessageType.text,
    String? replyToMessageId,
  }) {
    chatSocketService.sendMessage(
        sender: sender,
        content: content,
        type: type,
        replyToMessageId: replyToMessageId);
  }

  void disconnectFromChat() {
    chatSocketService.disconnect();
  }

  Future<void> sendVideoMessage({
    required String filePath,
    required String chatId,
    required String senderId,
  }) async {
    await _apiService.uploadVideo(
      filePath: filePath,
      chatId: chatId,
      senderId: senderId,
    );
  }

  Future<TranscriptionData?> transcribeMessage(String messageId) async {
    return await _apiService.getTranscriptionForMessage(messageId);
  }

  Future<void> fetchAndApplyTranscription(String messageId) async {
    final transcription = await _apiService.getTranscriptionForMessage(messageId);
    if (transcription != null) {
      final currentMessages = List<Message>.from(chatSocketService.messagesNotifier.value);
      final messageIndex = currentMessages.indexWhere((m) => m.id == messageId);

      if (messageIndex != -1) {
        final originalMessage = currentMessages[messageIndex];
        currentMessages[messageIndex] = originalMessage.withTranscription(transcription);
        chatSocketService.messagesNotifier.value = currentMessages;
      }
    }
  }

  Future<void> saveTranscription(String messageId, TranscriptionData data) async {
    final success = await _apiService.updateTranscriptionForMessage(messageId, data);
    if (success) {
      final currentMessages = List<Message>.from(chatSocketService.messagesNotifier.value);
      final messageIndex = currentMessages.indexWhere((m) => m.id == messageId);

      if (messageIndex != -1) {
        final originalMessage = currentMessages[messageIndex];
        currentMessages[messageIndex] = originalMessage.withTranscription(data);
        chatSocketService.messagesNotifier.value = currentMessages;
      }
    }
  }

  ValueNotifier<List<Message>> get messagesStream => chatSocketService.messagesNotifier;
}
