from pydantic import BaseModel, Field, ConfigDict, field_validator
from uuid import UUID as PyUUID
from datetime import datetime
from typing import Optional, List
from . import models

# --- Languages ---
class LanguageBase(BaseModel):
    name: str
    code: str

class LanguageInDB(LanguageBase):
    id: int
    model_config = ConfigDict(from_attributes=True)

class UserLanguageLink(BaseModel):
    id: int
    name: str
    code: str
    level: str
    type: str
    model_config = ConfigDict(from_attributes=True)

class LanguageUpdate(BaseModel):
    language_id: int
    level: str
    type: str

# --- Users ---
class UserCreate(BaseModel):
    username: str
    password: str

class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    gender: Optional[str] = None
    age: Optional[int] = None
    country: Optional[str] = None
    height: Optional[int] = None
    bio: Optional[str] = None
    avatar_url: Optional[str] = None
    interests: Optional[str] = None

class UserProfileResponse(BaseModel):
    id: PyUUID
    username: str
    full_name: Optional[str] = None
    gender: Optional[str] = None
    age: Optional[int] = None
    country: Optional[str] = None
    height: Optional[int] = None
    bio: Optional[str] = None
    avatar_url: Optional[str] = None
    interests: Optional[str] = None
    languages: List[UserLanguageLink] = []
    model_config = ConfigDict(from_attributes=True)

class ParticipantResponse(BaseModel):
    id: PyUUID
    username: str
    avatar_url: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

class UserInListResponse(UserProfileResponse):
    pass

# --- Tokens for authentication ---
class Token(BaseModel):
    access_token: str
    token_type: str
    user_id: PyUUID

class TokenData(BaseModel):
    username: Optional[str] = None

# --- Chats ---
class LastMessageSchema(BaseModel):
    content: str
    timestamp: datetime
    type: str
    model_config = ConfigDict(from_attributes=True)

class ChatCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=100, examples=["Project X Discussion"])

class ChatResponse(BaseModel):
    id: PyUUID
    title: Optional[str]
    timestamp: datetime
    participants: List[ParticipantResponse]
    last_message: Optional[LastMessageSchema] = None
    unread_count: int = 0
    model_config = ConfigDict(from_attributes=True)

class RepliedMessageInfo(BaseModel):
    id: PyUUID
    sender_id: PyUUID
    content: str
    type: str

    model_config = ConfigDict(from_attributes=True)

class MessageResponse(BaseModel):
    id: PyUUID
    chat_id: PyUUID
    sender_id: PyUUID
    content: str
    type: str
    timestamp: datetime
    replied_to_message: Optional[RepliedMessageInfo] = None

    model_config = ConfigDict(from_attributes=True)

class ChatWithParticipantsResponse(BaseModel):
    id: PyUUID
    title: Optional[str]
    timestamp: datetime
    participants: List[ParticipantResponse]
    model_config = ConfigDict(from_attributes=True)
