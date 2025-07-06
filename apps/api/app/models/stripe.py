from pydantic import BaseModel, EmailStr, Field
from typing import Optional
import re

class CreateCheckoutSessionRequest(BaseModel):
    user_id: str = Field(..., description="User ID for the checkout session")
    email: EmailStr = Field(..., description="Valid email address for the customer")
    price_id: str = Field(
        ..., 
        regex=r'^price_[a-zA-Z0-9]{14,}$',
        description="Stripe price ID (must start with 'price_' followed by at least 14 characters)"
    )
    subscription: bool = Field(default=False, description="Whether this is a subscription purchase")

class CreateCheckoutSessionResponse(BaseModel):
    session_id: str = Field(..., description="Stripe checkout session ID")
    
class StripeError(BaseModel):
    error: str = Field(..., description="Error message description")