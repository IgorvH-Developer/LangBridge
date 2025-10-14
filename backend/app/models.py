import uuid
from sqlalchemy import select, Column, String, Text, ForeignKey, TIMESTAMP, func, Integer, Table, \
    types, Boolean
from sqlalchemy.orm import relationship, remote, foreign
from sqlalchemy.ext.hybrid import hybrid_property
from .database import Base

# --- Custom UUID Type ---
class GUID(types.TypeDecorator):
    impl = types.CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == 'postgresql':
            from sqlalchemy.dialects.postgresql import UUID as PG_UUID
            return dialect.type_descriptor(PG_UUID(as_uuid=True))
        else:
            return dialect.type_descriptor(types.CHAR(32))

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        elif dialect.name == 'postgresql':
            return str(value)
        else:
            if not isinstance(value, uuid.UUID):
                return "%.32x" % uuid.UUID(value).int
            else:
                return "%.32x" % value.int

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        else:
            if not isinstance(value, uuid.UUID):
                value = uuid.UUID(value)
            return value

# --- Chat Participants Table ---
chat_participants = Table('chat_participants', Base.metadata,
                          Column('user_id', GUID, ForeignKey('users.id', ondelete="CASCADE"), primary_key=True),
                          Column('chat_id', GUID, ForeignKey('chats.id', ondelete="CASCADE"), primary_key=True),
                          # Добавляем поле для отслеживания последнего прочтения
                          Column('last_read_timestamp', TIMESTAMP, server_default=func.now())
                          )

# --- ORM MODELS ---

class Language(Base):
    __tablename__ = "languages"
    id = Column(Integer, primary_key=True)
    name = Column(String(100), unique=True, nullable=False)
    code = Column(String(10), unique=True, nullable=False)

class User(Base):
    __tablename__ = "users"
    id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    username = Column(String(100), unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)

    # Profile fields
    full_name = Column(String(150))
    gender = Column(String(50))
    age = Column(Integer)
    country = Column(String(100))
    height = Column(Integer)
    bio = Column(Text)
    avatar_url = Column(String)
    interests = Column(Text)

    # Relationships
    language_associations = relationship("UserLanguageAssociation", cascade="all, delete-orphan", back_populates="user")
    messages_sent = relationship("Message", back_populates="sender")
    chats = relationship("Chat", secondary=chat_participants, back_populates="participants")

class UserLanguageAssociation(Base):
    __tablename__ = 'user_languages'
    user_id = Column(GUID, ForeignKey('users.id'), primary_key=True)
    language_id = Column(Integer, ForeignKey('languages.id'), primary_key=True)
    level = Column(String(50))
    type = Column(String(20), primary_key=True)

    user = relationship("User", back_populates="language_associations")
    language = relationship("Language")

class Chat(Base):
    __tablename__ = "chats"
    id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    title = Column(String, nullable=True)
    timestamp = Column(TIMESTAMP, server_default=func.now())
    messages = relationship("Message", back_populates="chat", cascade="all, delete-orphan")
    participants = relationship("User", secondary=chat_participants, back_populates="chats")

    # This is a placeholder for the last message, to be populated manually
    _last_message = None

    @hybrid_property
    def last_message(self):
        return self._last_message

    @last_message.setter
    def last_message(self, message):
        self._last_message = message


class Message(Base):
    __tablename__ = "messages"
    id = Column(GUID(), primary_key=True, default=uuid.uuid4)
    chat_id = Column(GUID(), ForeignKey("chats.id", ondelete="CASCADE"))
    sender_id = Column(GUID(), ForeignKey("users.id"))
    content = Column(Text)
    type = Column(String, default="text")
    timestamp = Column(TIMESTAMP, server_default=func.now())
    is_read = Column(Boolean, default=False, nullable=False)

    reply_to_message_id = Column(GUID(), ForeignKey("messages.id"), nullable=True)

    # Отношение для получения сообщения, на которое был дан ответ
    replied_to_message = relationship(
        "Message",
        remote_side=[id], # Связь с самим собой по полю id
        backref="replies",
        uselist=False # У одного сообщения может быть только один ответ "на"
    )

    chat = relationship("Chat", back_populates="messages")
    sender = relationship("User", back_populates="messages_sent")
