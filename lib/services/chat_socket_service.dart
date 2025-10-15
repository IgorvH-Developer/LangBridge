import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

import 'package:LangBridge/config/app_config.dart';
import 'package:LangBridge/models/message.dart';
import 'package:LangBridge/repositories/auth_repository.dart';


class ChatSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  final Uuid _uuid = const Uuid();

  static final String _socketBaseUrl = "ws://${AppConfig.serverAddr}/ws/";

  bool get isConnected => _channel != null && _channelSubscription != null && !_channelSubscription!.isPaused;

  final ValueNotifier<List<Message>> messagesNotifier = ValueNotifier<List<Message>>([]);
  String? currentChatId;

  Future<void> connect(String chatId, List<Message> initialMessages) async {
    if (currentChatId == chatId && isConnected) {
      print("Уже подключен к чату: $chatId");
      return;
    }
    disconnect();

    currentChatId = chatId;
    messagesNotifier.value = List<Message>.from(initialMessages);

    // --- ИЗМЕНЕНИЕ: Получаем токен и добавляем его в URL ---
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: AuthRepository.accessTokenKey);
    if (token == null) {
      print("ОШИБКА: Токен не найден, WebSocket не может быть подключен.");
      // Можно добавить системное сообщение об ошибке
      messagesNotifier.value.add(Message(
        id: _uuid.v4(),
        senderId: 'system',
        content: 'Ошибка аутентификации. Не удалось подключиться к чату.',
        type: MessageType.text,
        timestamp: DateTime.now(),
      ));
      return;
    }

    final uri = Uri.parse("$_socketBaseUrl$chatId?token=$token");
    print("Подключение к WebSocket: $uri");

    _channel = WebSocketChannel.connect(uri);

    _channelSubscription = _channel!.stream.listen(
      (event) {
        print("Получено от сокета ($chatId): $event");
        try {
          final Map<String, dynamic> messageData = jsonDecode(event);
          final newMessage = Message.fromJson(messageData);

          final updatedMessages = List<Message>.from(messagesNotifier.value)..add(newMessage);
          messagesNotifier.value = updatedMessages;

        } catch (e) {
          print("Ошибка декодирования сообщения от сокета ($chatId): $e");
          final errorMessage = Message(
            id: _uuid.v4(),
            senderId: "system",
            content: "Ошибка обработки данных: $e",
            type: MessageType.text, // или специальный тип для ошибок
            timestamp: DateTime.now(),
          );
          final updatedMessages = List<Message>.from(messagesNotifier.value)..add(errorMessage);
          messagesNotifier.value = updatedMessages;
        }
      },
      onError: (error) {
        print("Ошибка WebSocket ($chatId): $error");
        final errorMessage = Message(
          id: _uuid.v4(),
          senderId: "system",
          content: "Ошибка соединения с чатом. Попробуйте позже.",
          type: MessageType.text,
          timestamp: DateTime.now(),
        );
        final updatedMessages = List<Message>.from(messagesNotifier.value)..add(errorMessage);
        messagesNotifier.value = updatedMessages;
        _channel = null;
      },
      onDone: () {
        print("WebSocket соединение закрыто для чата $chatId");
        if (currentChatId == chatId) {
          final systemMessage = Message(
            id: _uuid.v4(),
            senderId: "system",
            content: "Соединение с чатом завершено.",
            type: MessageType.text,
            timestamp: DateTime.now(),
          );
          final updatedMessages = List<Message>.from(messagesNotifier.value)..add(systemMessage);
          messagesNotifier.value = updatedMessages;
          currentChatId = null;
          _channel = null;
        }
      },
      cancelOnError: true,
    );
  }

  void sendMessage({
    required String sender,
    required String content,
    MessageType type = MessageType.text,
    String? replyToMessageId,
  }) {
    if (_channel == null || currentChatId == null) {
      print("Невозможно отправить сообщение: нет активного соединения с чатом.");
      final errorMessage = Message(
        id: _uuid.v4(),
        senderId: "system",
        content: "Не удалось отправить сообщение. Нет соединения.",
        type: MessageType.text,
        timestamp: DateTime.now(),
      );
      final updatedMessages = List<Message>.from(messagesNotifier.value)..add(errorMessage);
      messagesNotifier.value = updatedMessages;
      return;
    }

    final message = {
      'content': content,
      'type': type.toString().split('.').last,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
    };

    final messageJson = jsonEncode(message);
    print("Отправка сообщения ($currentChatId): $messageJson");
    _channel!.sink.add(messageJson);
  }

  void disconnect() {
    print("Отключение от чата: $currentChatId");
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _channelSubscription = null;
    _channel = null;
    currentChatId = null;
  }
}
