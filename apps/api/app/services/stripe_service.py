import stripe
from app.config import settings
from app.models.stripe import CreateCheckoutSessionRequest

stripe.api_key = settings.STRIPE_SECRET_KEY

class StripeService:
    @staticmethod
    async def create_checkout_session(data: CreateCheckoutSessionRequest) -> dict:
        """Create a Stripe checkout session"""
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
        
        session = stripe.checkout.Session.create(**session_params)
        return {"session_id": session.id}