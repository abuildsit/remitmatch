from fastapi import HTTPException, Header, Depends
from jose import JWTError, jwt
from typing import Optional, Dict, Any
import httpx
import structlog
from app.config import settings

logger = structlog.get_logger(__name__)

class ClerkAuth:
    """Minimal JWT authentication for Clerk"""
    
    def __init__(self):
        self.jwks_cache: Optional[Dict[str, Any]] = None
    
    async def get_jwks(self) -> Dict[str, Any]:
        """Get JWKS from Clerk (cached)"""
        if self.jwks_cache is None:
            try:
                async with httpx.AsyncClient() as client:
                    response = await client.get(f"https://clerk.{settings.CLERK_DOMAIN}/.well-known/jwks.json")
                    response.raise_for_status()
                    self.jwks_cache = response.json()
            except Exception as e:
                logger.error("Failed to fetch JWKS", error=str(e))
                raise HTTPException(status_code=500, detail="Authentication service unavailable")
        
        return self.jwks_cache
    
    async def verify_token(self, token: str) -> Dict[str, Any]:
        """Verify JWT token and extract user data"""
        try:
            # Get JWKS for token verification
            jwks = await self.get_jwks()
            
            # Decode token header to get kid
            unverified_header = jwt.get_unverified_header(token)
            kid = unverified_header.get("kid")
            
            if not kid:
                raise HTTPException(status_code=401, detail="Invalid token format")
            
            # Find the correct key
            key = None
            for jwk in jwks["keys"]:
                if jwk["kid"] == kid:
                    key = jwk
                    break
            
            if not key:
                raise HTTPException(status_code=401, detail="Invalid token key")
            
            # Verify and decode token
            payload = jwt.decode(
                token,
                key,
                algorithms=["RS256"],
                audience=settings.CLERK_AUDIENCE,
                issuer=f"https://clerk.{settings.CLERK_DOMAIN}"
            )
            
            # Extract user data
            user_data = {
                "user_id": payload.get("sub"),
                "email": payload.get("email"),
                "session_id": payload.get("sid")
            }
            
            if not user_data["user_id"]:
                raise HTTPException(status_code=401, detail="Invalid token payload")
            
            return user_data
            
        except JWTError as e:
            logger.error("JWT verification failed", error=str(e))
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        except Exception as e:
            logger.error("Unexpected authentication error", error=str(e))
            raise HTTPException(status_code=500, detail="Authentication failed")

# Global auth instance
clerk_auth = ClerkAuth()

async def verify_token(authorization: Optional[str] = Header(None)) -> Dict[str, Any]:
    """FastAPI dependency for JWT verification"""
    if not authorization:
        raise HTTPException(status_code=401, detail="Authorization header required")
    
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization format")
    
    token = authorization.split(" ")[1]
    return await clerk_auth.verify_token(token)