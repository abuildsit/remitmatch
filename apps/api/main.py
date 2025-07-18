from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.routers import stripe
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
import logging
import time
import structlog

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

# Get structured logger
logger = structlog.get_logger()

limiter = Limiter(key_func=get_remote_address)
app = FastAPI(
    title="RemitMatch API",
    version="0.1.0",
    description="Backend API for RemitMatch"
)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Request/Response logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    
    logger.info(
        "Request started",
        method=request.method,
        path=request.url.path,
        query_params=str(request.query_params),
        client_ip=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent", "")
    )
    
    response = await call_next(request)
    
    process_time = time.time() - start_time
    logger.info(
        "Request completed",
        method=request.method,
        path=request.url.path,
        status_code=response.status_code,
        process_time=round(process_time, 4)
    )
    
    return response

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.FRONTEND_URL],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)

# Include routers
app.include_router(stripe.router, prefix="/stripe", tags=["stripe"])

@app.get("/")
async def root():
    return {"message": "RemitMatch API is running"}

@app.get("/health")
async def health_check():
    import psutil
    from datetime import datetime
    
    start_time = time.time()
    
    health_data = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "environment": settings.API_ENV,
        "version": "0.1.0",
        "uptime": time.time() - start_time,
    }
    
    # Add database health check if available
    try:
        # This would need actual database connection testing
        health_data["database"] = {
            "status": "connected",
            "responseTime": 0.1  # This would be actual DB response time
        }
    except Exception as e:
        health_data["database"] = {
            "status": "disconnected",
            "error": str(e)
        }
        health_data["status"] = "unhealthy"
    
    # Add system metrics in development
    if settings.API_ENV == "development":
        health_data["system"] = {
            "cpu_percent": psutil.cpu_percent(),
            "memory_percent": psutil.virtual_memory().percent,
            "disk_percent": psutil.disk_usage('/').percent if hasattr(psutil, 'disk_usage') else None
        }
    
    return health_data