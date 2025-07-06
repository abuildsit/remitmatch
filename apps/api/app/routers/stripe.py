from fastapi import APIRouter, HTTPException
from app.models.stripe import (
    CreateCheckoutSessionRequest,
    CreateCheckoutSessionResponse,
    StripeError
)
from app.services.stripe_service import StripeService
import stripe

router = APIRouter()

@router.post(
    "/checkout",
    response_model=CreateCheckoutSessionResponse,
    responses={400: {"model": StripeError}}
)
async def create_checkout_session(request: CreateCheckoutSessionRequest):
    """Create a Stripe checkout session for subscription or one-time payment"""
    try:
        result = await StripeService.create_checkout_session(request)
        return CreateCheckoutSessionResponse(session_id=result["session_id"])
    except stripe.error.StripeError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to create checkout session")

@router.get("/test")
async def test_stripe():
    return {"message": "Stripe router is working"}