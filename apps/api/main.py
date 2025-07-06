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