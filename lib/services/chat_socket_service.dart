import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

import 'package:LangBridge/config/app_config.dart';
import 'package:LangBridge/models/message.dart';

// Интерфейс для обратного вызова при получении нового сообщения
typedef OnMessageReceivedCallback = void Function(Message message);

class ChatSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  final Uuid _uuid = const Uuid();

  // 10.0.2.2 для Android эмулятора, если сервер локально.
  // 'ws://your_server_domain.com/ws/' для развернутого сервера.

  // static const String _socketBaseUrl = "ws://10.0.2.2/ws/"; // Пример для локального сервера и Android эмулятора
  static final String _socketBaseUrl = "ws://${AppConfig.serverAddr}/ws/"; // Адрес сервера для приложений извне

  bool get isConnected => _channel != null && _channelSubscription != null && !_channelSubscription!.isPaused;

  // Используем ValueNotifier для уведомления UI об изменениях списка сообщений
  // Это простой способ, для более сложных сценариев рассмотрите Bloc или Riverpod
  final ValueNotifier<List<Message>> messagesNotifier = ValueNotifier<List<Message>>([]);
  String? currentChatId; // Made public

  void connect(String chatId, List<Message> initialMessages) {
    if (currentChatId == chatId && isConnected) { // Updated usage
      print("Уже подключен к чату: $chatId");
      return;
    }
    disconnect(); // Закрываем предыдущее соединение, если есть

    currentChatId = chatId; // Updated usage
    messagesNotifier.value = List<Message>.from(initialMessages); // Инициализируем сообщениями из Chat
    final uri = Uri.parse("$_socketBaseUrl$chatId");
    print("Подключение к WebSocket: $uri");

    _channel = WebSocketChannel.connect(uri);

    _channelSubscription = _channel!.stream.listen(
      (event) {
        print("Получено от сокета ($chatId): $event");
        try {
          final Map<String, dynamic> messageData = jsonDecode(event);
          // !!! ВАЖНО: Убедитесь, что Message.fromJson корректно обрабатывает данные от сервера
          // Например, сервер может не отправлять 'id' или 'timestamp', их можно генерировать на клиенте
          // или ожидать от сервера. Также поля 'sender', 'content', 'type'.
          final newMessage = Message.fromJson(messageData); // Предполагаем, что у вас есть Message.fromJson

          // Добавляем сообщение в начало списка для отображения новых сверху или в конец, если reverse в ListView
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
        _channel = null; // Сбрасываем канал
      },
      onDone: () {
        print("WebSocket соединение закрыто для чата $chatId");
        if (currentChatId == chatId) { // Updated usage // Только если это текущее активное соединение
          final systemMessage = Message(
            id: _uuid.v4(),
            senderId: "system",
            content: "Соединение с чатом завершено.",
            type: MessageType.text,
            timestamp: DateTime.now(),
          );
          final updatedMessages = List<Message>.from(messagesNotifier.value)..add(systemMessage);
          messagesNotifier.value = updatedMessages;
          currentChatId = null; // Updated usage
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

    final message = Message(
      id: _uuid.v4(), // Клиент генерирует ID для оптимистичного обновления
      senderId: sender,
      content: content,
      type: type,
      timestamp: DateTime.now(),
    );

    final messageJson = jsonEncode({
      'sender_id': message.senderId,
      'content': message.content,
      'type': message.type.toString().split('.').last,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
    });
    print("Отправка сообщения ($currentChatId): $messageJson"); // Updated usage
    _channel!.sink.add(messageJson);
  }

  void disconnect() {
    print("Отключение от чата: $currentChatId"); // Updated usage
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _channelSubscription = null;
    _channel = null;
    // Очищать ли messagesNotifier.value здесь - зависит от вашей логики.
    // Если при выходе с экрана чата сообщения должны исчезать, то да.
    // messagesNotifier.value = []; // Опционально
    currentChatId = null; // Updated usage
  }
}
