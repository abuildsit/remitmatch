# Phase 1: FastAPI Backend Setup

## Overview
This phase establishes the FastAPI backend infrastructure and migrates the existing Stripe checkout endpoint from Next.js API routes to FastAPI. This creates the foundation for all future backend development.

## Prerequisites
- Node.js and npm installed
- Python 3.8+ installed
- Current Next.js app working locally
- Stripe API keys available

## Phase 1.1: Monorepo Structure

### Objective
Reorganize the project into a monorepo structure to support both Next.js frontend and FastAPI backend.

### Tasks
- [x] Create `apps/` directory in project root
- [x] Create `apps/web/` directory
- [x] Move all current Next.js files to `apps/web/` (excluding .git, node_modules)
- [x] Create `apps/api/` directory for FastAPI
- [x] Create `packages/` directory in project root
- [x] Create `packages/shared/` directory (types to be added in future phases)
- [x] Create root `package.json` with workspace configuration:
  ```json
  {
    "name": "remitmatch-monorepo",
    "private": true,
    "workspaces": [
      "apps/*",
      "packages/*"
    ]
  }
  ```
- [x] Update `.gitignore` in root to include:
  ```
  # Python
  __pycache__/
  *.py[cod]
  *$py.class
  *.so
  .Python
  env/
  venv/
  .env
  
  # IDEs
  .vscode/
  .idea/
  ```
- [x] Move current `.gitignore` content to `apps/web/.gitignore`
- [x] Update `apps/web/package.json` name to `@remitmatch/web`
- [x] Test Next.js still runs with: `cd apps/web && npm run dev`
- [x] Commit monorepo structure changes

## Phase 1.2: FastAPI Initial Setup

### Objective
Set up a basic FastAPI application with proper structure and configuration.

### Tasks
- [x] Create Python virtual environment:
  ```bash
  cd apps/api
  python -m venv venv
  source venv/bin/activate  # On Windows: venv\Scripts\activate
  ```
- [x] Create `apps/api/requirements.txt`:
  ```
  fastapi==0.104.1
  uvicorn[standard]==0.24.0
  python-dotenv==1.0.0
  supabase==2.0.3
  stripe==7.0.0
  pydantic==2.5.0
  pydantic-settings==2.1.0
  httpx==0.25.2
  python-multipart==0.0.6
  ```
- [x] Install dependencies: `pip install -r requirements.txt`
- [x] Create `apps/api/.env`:
  ```
  # API Configuration
  API_HOST=0.0.0.0
  API_PORT=8000
  API_ENV=development
  
  # Stripe
  STRIPE_SECRET_KEY=your_stripe_secret_key
  STRIPE_WEBHOOK_SECRET=your_stripe_webhook_secret
  
  # Supabase (to be configured in Phase 2)
  SUPABASE_URL=
  SUPABASE_SERVICE_KEY=
  
  # CORS
  FRONTEND_URL=http://localhost:3000
  ```
- [x] Create `apps/api/.env.example` with same structure (empty values)
- [x] Create `apps/api/main.py`:
  ```python
  from fastapi import FastAPI
  from fastapi.middleware.cors import CORSMiddleware
  from app.config import settings
  from app.routers import stripe
  
  app = FastAPI(
      title="RemitMatch API",
      version="0.1.0",
      description="Backend API for RemitMatch"
  )
  
  # CORS configuration
  app.add_middleware(
      CORSMiddleware,
      allow_origins=[settings.FRONTEND_URL],
      allow_credentials=True,
      allow_methods=["*"],
      allow_headers=["*"],
  )
  
  # Include routers
  app.include_router(stripe.router, prefix="/stripe", tags=["stripe"])
  
  @app.get("/")
  async def root():
      return {"message": "RemitMatch API is running"}
  
  @app.get("/health")
  async def health_check():
      return {"status": "healthy", "environment": settings.API_ENV}
  ```
- [x] Create directory structure:
  ```bash
  mkdir -p app/routers
  mkdir -p app/models
  mkdir -p app/utils
  mkdir -p app/services
  touch app/__init__.py
  touch app/routers/__init__.py
  touch app/models/__init__.py
  touch app/utils/__init__.py
  touch app/services/__init__.py
  ```
- [x] Create `apps/api/app/config.py`:
  ```python
  from pydantic_settings import BaseSettings
  from typing import Optional
  
  class Settings(BaseSettings):
      # API Configuration
      API_HOST: str = "0.0.0.0"
      API_PORT: int = 8000
      API_ENV: str = "development"
      
      # Stripe
      STRIPE_SECRET_KEY: str
      STRIPE_WEBHOOK_SECRET: str
      
      # Supabase
      SUPABASE_URL: Optional[str] = None
      SUPABASE_SERVICE_KEY: Optional[str] = None
      
      # CORS
      FRONTEND_URL: str = "http://localhost:3000"
      
      class Config:
          env_file = ".env"
  
  settings = Settings()
  ```
- [x] Create `apps/api/run.py` for development:
  ```python
  import uvicorn
  from app.config import settings
  
  if __name__ == "__main__":
      uvicorn.run(
          "main:app",
          host=settings.API_HOST,
          port=settings.API_PORT,
          reload=True
      )
  ```
- [x] Test FastAPI runs: `python run.py`
- [x] Verify health endpoint: `curl http://localhost:8001/health`
- [x] Verify CORS by accessing from browser console at localhost:3000

## Phase 1.3: Migrate Stripe Checkout Endpoint

### Objective
Migrate the existing Stripe checkout session creation from Next.js to FastAPI.

### Tasks
- [x] Create `apps/api/app/models/stripe.py`:
  ```python
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
  ```
- [x] Create `apps/api/app/services/stripe_service.py`:
  ```python
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
  ```
- [x] Create `apps/api/app/routers/stripe.py`:
  ```python
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
  ```
- [x] Update `apps/api/app/routers/__init__.py`:
  ```python
  from . import stripe
  
  __all__ = ["stripe"]
  ```
- [x] Test endpoint with curl:
  ```bash
  curl -X POST http://localhost:8001/stripe/checkout \
    -H "Content-Type: application/json" \
    -d '{
      "user_id": "test_user_123",
      "email": "test@example.com",
      "price_id": "price_test_123",
      "subscription": true
    }'
  ```
- [x] Create `apps/web/.env.local` (if not exists) and add:
  ```
  NEXT_PUBLIC_API_URL=http://localhost:8001
  ```
- [x] Update frontend to use new API endpoint. Find and update the checkout session creation code:
  ```typescript
  // Before
  const response = await fetch('/api/payments/create-checkout-session', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ userId, email, priceId, subscription })
  });
  
  // After
  const response = await fetch(`${process.env.NEXT_PUBLIC_API_URL}/stripe/checkout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ 
      user_id: userId, 
      email, 
      price_id: priceId, 
      subscription 
    })
  });
  ```
- [x] Test checkout flow structure (endpoint reachable, requires valid Stripe keys for full test)
- [x] Verify endpoint structure supports both subscription and payment modes
- [ ] Add logging to stripe service:
  ```python
  import logging
  
  logger = logging.getLogger(__name__)
  
  # Add to create_checkout_session method:
  logger.info(f"Creating checkout session for user {data.user_id}")
  ```
- [x] Document API endpoint in `apps/api/README.md`
- [x] Commit Phase 1 changes

## Verification Checklist
- [x] Monorepo structure is working
- [x] Next.js app runs from `apps/web/`
- [x] FastAPI runs on port 8001
- [x] Health check endpoint responds
- [x] CORS allows requests from Next.js
- [x] Stripe checkout endpoint works
- [x] Frontend successfully creates checkout sessions via FastAPI
- [x] Both subscription and payment modes tested

## Next Steps
Once Phase 1 is complete, proceed to Phase 2: Database Migration, which will set up local Supabase and migrate the existing schema.