import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, Header
from sqlalchemy.orm import Session
from uuid import UUID as PyUUID
from datetime import datetime
from jose import jwt, JWTError

from .. import database, models, schemas, security
from ..websocket_manager import ConnectionManager
from ..logger import logger

router = APIRouter(prefix="/ws", tags=["websocket"])

manager = ConnectionManager()

async def get_user_from_token(token: str, db: Session) -> models.User | None:
    if not token:
        return None
    try:
        payload = jwt.decode(token, security.SECRET_KEY, algorithms=[security.ALGORITHM])
        user_id = payload.get("user_id")
        if user_id is None:
            return None
        return db.query(models.User).filter(models.User.id == PyUUID(user_id)).first()
    except (JWTError, ValueError):
        return None

@router.websocket("/{chat_id_str}")
async def websocket_endpoint(
        websocket: WebSocket,
        chat_id_str: str,
        db: Session = Depends(database.get_db),
):
    # 1. Извлекаем токен из query-параметров
    token = websocket.query_params.get("token")
    if not token:
        logger.warning(f"WebSocket connection attempt for chat {chat_id_str} without token.")
        await websocket.close(code=1008)
        return

    # 2. Аутентифицируем пользователя по токену
    user = await get_user_from_token(token, db)
    if not user:
        logger.warning(f"WebSocket connection failed for chat {chat_id_str}: Invalid token.")
        await websocket.close(code=1008)
        return

    # 3. Валидируем UUID чата
    try:
        chat_uuid_obj = PyUUID(chat_id_str)
    except ValueError:
        await websocket.close(code=1008)
        return

    # 4. Проверяем, что чат существует и пользователь является его участником
    chat = db.query(models.Chat).filter(models.Chat.id == chat_uuid_obj).first()
    is_participant = any(p.id == user.id for p in chat.participants)
    if not chat or not is_participant:
        await websocket.close(code=1003)
        return

    # 5. Подключаем пользователя
    await manager.connect(chat_id_str, websocket)

    try:
        while True:
            data = await websocket.receive_json()
            logger.debug(f"Received from user {user.id} in chat {chat_id_str}: {data}")

            # --- ИСПРАВЛЕНИЕ: Используем ID аутентифицированного пользователя ---
            sender_id = user.id
            content = data.get("content")
            if not content:
                continue

            reply_to_id = data.get("reply_to_message_id")
            reply_to_uuid = None
            if reply_to_id:
                try:
                    reply_to_uuid = PyUUID(reply_to_id)
                except ValueError:
                    pass

            # Создание сообщения в БД
            db_message = models.Message(
                chat_id=chat_uuid_obj,
                sender_id=sender_id, # <<< ИСПРАВЛЕНО
                content=content,
                type=data.get("type", "text"),
                reply_to_message_id=reply_to_uuid
            )
            db.add(db_message)
            db.commit()
            db.refresh(db_message)

            replied_message_info = None
            if db_message.replied_to_message:
                replied_message_info = schemas.RepliedMessageInfo.model_validate(
                    db_message.replied_to_message
                ).model_dump()

            # Сериализуем сообщение для отправки клиентам
            message_for_broadcast = schemas.MessageResponse.model_validate(db_message).model_dump_json()

            # manager.broadcast теперь сам парсит JSON, отправляем словарь
            await manager.broadcast(chat_id_str, json.loads(message_for_broadcast))

    except WebSocketDisconnect:
        logger.info(f"Client {user.id} disconnected from chat {chat_id_str}")
    except Exception as e:
        logger.error(f"Unexpected error in WebSocket for chat {chat_id_str}: {e}", exc_info=True)
    finally:
        # --- ИСПРАВЛЕНИЕ: Упрощенный и надежный disconnect ---
        # Просто удаляем соединение из менеджера. Проверка состояния не нужна.
        manager.disconnect(chat_id_str, websocket)
        logger.info(f"WebSocket for user {user.id} in chat {chat_id_str} is fully closed.")
