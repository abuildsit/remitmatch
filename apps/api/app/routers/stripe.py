from fastapi import APIRouter, HTTPException, Request, Depends
from app.models.stripe import (
    CreateCheckoutSessionRequest,
    CreateCheckoutSessionResponse,
    StripeError
)
from app.services.stripe_service import StripeService
from app.config import settings
from app.middleware.auth import verify_token
import stripe
import structlog
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from typing import Dict, Any
import httpx

logger = structlog.get_logger(__name__)

limiter = Limiter(key_func=get_remote_address)
router = APIRouter()

@router.post(
    "/checkout",
    response_model=CreateCheckoutSessionResponse,
    responses={400: {"model": StripeError}}
)
@limiter.limit("10/minute")
async def create_checkout_session(
    request: Request, 
    data: CreateCheckoutSessionRequest,
    user: Dict[str, Any] = Depends(verify_token)
):
    """Create a Stripe checkout session for subscription or one-time payment"""
    try:
        # Use user data from JWT instead of request body
        authenticated_data = CreateCheckoutSessionRequest(
            user_id=user["user_id"],
            email=user["email"],
            price_id=data.price_id,
            subscription=data.subscription
        )
        
        result = await StripeService.create_checkout_session(authenticated_data)
        return CreateCheckoutSessionResponse(session_id=result["session_id"])
    except stripe.error.CardError as e:
        logger.error("Stripe card error", error=str(e), user_id=user["user_id"])
        raise HTTPException(status_code=400, detail="Payment card was declined")
    except stripe.error.RateLimitError as e:
        logger.error("Stripe rate limit error", error=str(e), user_id=user["user_id"])
        raise HTTPException(status_code=429, detail="Too many requests to payment processor")
    except stripe.error.InvalidRequestError as e:
        logger.error("Stripe invalid request error", error=str(e), user_id=user["user_id"])
        raise HTTPException(status_code=400, detail="Invalid payment request")
    except stripe.error.AuthenticationError as e:
        logger.error("Stripe authentication error", error=str(e), user_id=user["user_id"])
        raise HTTPException(status_code=500, detail="Payment processor authentication failed")
    except stripe.error.APIConnectionError as e:
        logger.error("Stripe API connection error", error=str(e), user_id=user["user_id"])
        raise HTTPException(status_code=503, detail="Payment processor unavailable")
    except stripe.error.StripeError as e:
        logger.error("General Stripe error", error=str(e), user_id=user["user_id"])
        raise HTTPException(status_code=500, detail="Payment processing error")
    except Exception as e:
        logger.error("Unexpected error during checkout session creation", 
                    error=str(e), user_id=user["user_id"], price_id=data.price_id)
        raise HTTPException(status_code=500, detail="Payment processing failed")

@router.post("/webhook")
async def stripe_webhook(request: Request):
    """Handle Stripe webhook events"""
    payload = await request.body()
    sig_header = request.headers.get('stripe-signature')
    
    if not sig_header:
        raise HTTPException(status_code=400, detail="Missing stripe-signature header")
    
    try:
        event = StripeService.verify_webhook_signature(payload, sig_header)
    except ValueError as e:
        logger.error("Webhook verification failed", error=str(e))
        raise HTTPException(status_code=400, detail="Invalid signature or payload")
    
    # Log the event for debugging
    logger.info("Received Stripe webhook event", event_type=event['type'])
    
    # Handle different event types
    if event['type'] == 'checkout.session.completed':
        session = event['data']['object']
        logger.info("Payment succeeded for session", session_id=session['id'])
        
        try:
            # Delegate to Next.js API for database operations
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{settings.FRONTEND_URL}/api/payments/webhook",
                    json={
                        "type": event['type'],
                        "data": event['data']
                    },
                    timeout=30.0
                )
                
                if response.status_code == 200:
                    logger.info("Successfully delegated webhook to Next.js API", session_id=session['id'])
                else:
                    logger.error("Failed to delegate webhook to Next.js API", 
                               session_id=session['id'], status_code=response.status_code)
                    
        except Exception as e:
            logger.error("Error delegating webhook to Next.js API", 
                        session_id=session['id'], error=str(e))
        
    else:
        logger.info("Unhandled event type", event_type=event['type'])
    
    return {"status": "success"}

@router.get("/test")
async def test_stripe():
    return {"message": "Stripe router is working"}