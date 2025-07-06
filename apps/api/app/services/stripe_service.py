import stripe
from app.config import settings
from app.models.stripe import CreateCheckoutSessionRequest
import structlog

logger = structlog.get_logger(__name__)

class StripeService:
    @staticmethod
    def _initialize_stripe():
        """Initialize Stripe API key"""
        stripe.api_key = settings.STRIPE_SECRET_KEY
    
    @staticmethod
    def verify_webhook_signature(payload: bytes, signature: str) -> dict:
        """Verify Stripe webhook signature and return event"""
        try:
            event = stripe.Webhook.construct_event(
                payload, signature, settings.STRIPE_WEBHOOK_SECRET
            )
            return event
        except (ValueError, stripe.error.SignatureVerificationError) as e:
            raise ValueError(f"Webhook signature verification failed: {str(e)}")
    
    @staticmethod
    async def create_checkout_session(data: CreateCheckoutSessionRequest) -> dict:
        """Create a Stripe checkout session"""
        logger.info(
            "Creating Stripe checkout session",
            user_id=data.user_id,
            email=data.email,
            price_id=data.price_id,
            subscription=data.subscription
        )
        
        StripeService._initialize_stripe()
        session_params = {
            "payment_method_types": ["card"],
            "line_items": [{"price": data.price_id, "quantity": 1}],
            "metadata": {
                "userId": data.user_id,
                "email": data.email,
                "subscription": str(data.subscription)
            },
            "success_url": f"{settings.FRONTEND_URL}/success?session_id={{CHECKOUT_SESSION_ID}}",
            "cancel_url": f"{settings.FRONTEND_URL}/cancel",
        }
        
        if data.subscription:
            session_params["mode"] = "subscription"
            session_params["allow_promotion_codes"] = True
        else:
            session_params["mode"] = "payment"
        
        try:
            session = stripe.checkout.Session.create(**session_params)
            logger.info(
                "Stripe checkout session created successfully",
                session_id=session.id,
                user_id=data.user_id
            )
            return {"session_id": session.id}
        except Exception as e:
            logger.error(
                "Failed to create Stripe checkout session",
                error=str(e),
                user_id=data.user_id,
                price_id=data.price_id
            )
            raise