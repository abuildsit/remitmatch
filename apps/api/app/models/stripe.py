from pydantic import BaseModel
from typing import Optional

class CreateCheckoutSessionRequest(BaseModel):
    user_id: str
    email: str
    price_id: str
    subscription: bool = False

class CreateCheckoutSessionResponse(BaseModel):
    session_id: str
    
class StripeError(BaseModel):
    error: str