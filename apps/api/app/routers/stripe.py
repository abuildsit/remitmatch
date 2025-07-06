from fastapi import APIRouter, HTTPException, Request
from app.models.stripe import (
    CreateCheckoutSessionRequest,
    CreateCheckoutSessionResponse,
    StripeError
)
from app.services.stripe_service import StripeService
from app.config import settings
import stripe
import structlog
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

logger = structlog.get_logger(__name__)

limiter = Limiter(key_func=get_remote_address)
router = APIRouter()

@router.post(
    "/checkout",
    response_model=CreateCheckoutSessionResponse,
    responses={400: {"model": StripeError}}
)
@limiter.limit("10/minute")
async def create_checkout_session(request: Request, data: CreateCheckoutSessionRequest):
    """Create a Stripe checkout session for subscription or one-time payment"""
    try:
        result = await StripeService.create_checkout_session(data)
        return CreateCheckoutSessionResponse(session_id=result["session_id"])
    except stripe.error.CardError as e:
        logger.error("Stripe card error", error=str(e), user_id=data.user_id)
        raise HTTPException(status_code=400, detail="Payment card was declined")
    except stripe.error.RateLimitError as e:
        logger.error("Stripe rate limit error", error=str(e), user_id=data.user_id)
        raise HTTPException(status_code=429, detail="Too many requests to payment processor")
    except stripe.error.InvalidRequestError as e:
        logger.error("Stripe invalid request error", error=str(e), user_id=data.user_id)
        raise HTTPException(status_code=400, detail="Invalid payment request")
    except stripe.error.AuthenticationError as e:
        logger.error("Stripe authentication error", error=str(e), user_id=data.user_id)
        raise HTTPException(status_code=500, detail="Payment processor authentication failed")
    except stripe.error.APIConnectionError as e:
        logger.error("Stripe API connection error", error=str(e), user_id=data.user_id)
        raise HTTPException(status_code=503, detail="Payment processor unavailable")
    except stripe.error.StripeError as e:
        logger.error("General Stripe error", error=str(e), user_id=data.user_id)
        raise HTTPException(status_code=500, detail="Payment processing error")
    except Exception as e:
        logger.error("Unexpected error during checkout session creation", 
                    error=str(e), user_id=data.user_id, price_id=data.price_id)
        raise HTTPException(status_code=500, detail="An unexpected error occurred")

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
        logger.error(f"Webhook verification failed: {e}")
        raise HTTPException(status_code=400, detail="Invalid signature or payload")
    
    # Log the event for debugging
    logger.info(f"Received Stripe webhook event: {event['type']}")
    
    # Handle different event types
    if event['type'] == 'checkout.session.completed':
        session = event['data']['object']
        logger.info(f"Payment succeeded for session: {session['id']}")
        # TODO: Update your database with successful payment
        # Example: mark order as paid, send confirmation email, etc.
        
    elif event['type'] == 'payment_intent.succeeded':
        payment_intent = event['data']['object']
        logger.info(f"Payment intent succeeded: {payment_intent['id']}")
        # TODO: Handle successful payment intent
        
    elif event['type'] == 'invoice.payment_succeeded':
        invoice = event['data']['object']
        logger.info(f"Invoice payment succeeded: {invoice['id']}")
        # TODO: Handle successful subscription payment
        
    elif event['type'] == 'customer.subscription.created':
        subscription = event['data']['object']
        logger.info(f"Subscription created: {subscription['id']}")
        # TODO: Handle new subscription
        
    elif event['type'] == 'customer.subscription.updated':
        subscription = event['data']['object']
        logger.info(f"Subscription updated: {subscription['id']}")
        # TODO: Handle subscription changes
        
    elif event['type'] == 'customer.subscription.deleted':
        subscription = event['data']['object']
        logger.info(f"Subscription cancelled: {subscription['id']}")
        # TODO: Handle subscription cancellation
        
    else:
        logger.info(f"Unhandled event type: {event['type']}")
    
    return {"status": "success"}

@router.get("/test")
async def test_stripe():
    return {"message": "Stripe router is working"}