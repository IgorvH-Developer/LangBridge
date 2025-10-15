from typing import Dict, List
from fastapi import WebSocket
from .logger import logger

class ConnectionManager:
    def __init__(self):
        # ключ = chat_id, значение = список соединений
        self.active_connections: Dict[str, List[WebSocket]] = {}

    async def connect(self, chat_id: str, websocket: WebSocket):
        logger.info(f"Got connection request for {chat_id}")
        await websocket.accept()
        if chat_id not in self.active_connections:
            self.active_connections[chat_id] = []
        self.active_connections[chat_id].append(websocket)
        logger.info(f"Accepted connection for {chat_id}. Total connections for chat: {len(self.active_connections[chat_id])}")

    def disconnect(self, chat_id: str, websocket: WebSocket):
        logger.info(f"Processing disconnect for chat {chat_id}")
        if chat_id in self.active_connections:
            try:
                self.active_connections[chat_id].remove(websocket)
                logger.info(f"Removed websocket from chat {chat_id}.")
                # Если в чате не осталось участников, удаляем сам чат из словаря
                if not self.active_connections[chat_id]:
                    logger.info(f"Chat {chat_id} is now empty. Removing from manager.")
                    del self.active_connections[chat_id]
            except ValueError:
                # Это нормально, если сокет уже был удален (например, в broadcast)
                logger.warning(f"Tried to disconnect a websocket that was not in the list for chat {chat_id}.")
                pass

    async def broadcast(self, chat_id: str, message: dict):
        logger.info(f"Broadcasting to chat {chat_id}")
        if chat_id in self.active_connections:
            # Итерируемся по копии списка, чтобы избежать проблем при изменении списка во время итерации
            for connection in self.active_connections[chat_id][:]:
                try:
                    await connection.send_json(message)
                except RuntimeError as e:
                    # Эта ошибка возникает, если сокет внезапно закрылся.
                    # Просто удаляем его и продолжаем работу.
                    logger.warning(f"Failed to send to a closed websocket in chat {chat_id}. Removing it. Error: {e}")
                    self.disconnect(chat_id, connection)
