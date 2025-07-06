# PR #1 Review - Action Items

## Overview
This document contains the atomic task list for resolving issues identified in the FastAPI Backend Setup (Phase 1) PR review.

## 🔴 CRITICAL - Must Fix Before Merge

### Task 1: Fix Duplicate Directory Structure - [x] COMPLETED
- **File**: `apps/api/apps/api/`
- **Action**: Remove the duplicate nested directory structure
- **Steps**:
  1. Navigate to `apps/api/`
  2. Remove the nested `apps/api/` directory
  3. Ensure all files are properly located in the root `apps/api/` structure
  4. Update any import paths if necessary
- **Priority**: Critical
- **Estimated Time**: 15 minutes

### Task 2: Secure API Key Management - [x] COMPLETED
- **File**: `apps/api/app/services/stripe_service.py`
- **Action**: Move Stripe API key initialization from module level to service method
- **Steps**:
  1. Remove `stripe.api_key = settings.STRIPE_SECRET_KEY` from module level
  2. Add API key initialization inside the `create_checkout_session` method
  3. Consider creating a private method `_initialize_stripe()` for reusability
  4. Ensure API key is set before each Stripe API call
- **Priority**: Critical
- **Estimated Time**: 30 minutes

### Task 3: Add Input Validation - [x] COMPLETED
- **File**: `apps/api/app/models/stripe.py`
- **Action**: Add field validation for email and price_id
- **Steps**:
  1. Import `EmailStr` from `pydantic`
  2. Change `email: str` to `email: EmailStr`
  3. Add regex validation for `price_id` field
  4. Add field descriptions for API documentation
- **Priority**: Critical
- **Estimated Time**: 20 minutes

### Task 4: Resolve Port Configuration Mismatch - [x] COMPLETED
- **File**: `apps/api/app/config.py` and `apps/api/.env.example`
- **Action**: Standardize port configuration
- **Steps**:
  1. Choose standard port (recommend 8001 for API)
  2. Update `config.py` to use consistent port
  3. Update `.env.example` to match
  4. Update documentation to reflect correct port
- **Priority**: Critical
- **Estimated Time**: 10 minutes

## 🟡 HIGH PRIORITY - Should Fix for Production

### Task 5: Add Rate Limiting - [x] COMPLETED
- **File**: `apps/api/app/routers/stripe.py`
- **Action**: Implement rate limiting for payment endpoints
- **Steps**:
  1. Add `slowapi` dependency to `requirements.txt`
  2. Create rate limiting middleware
  3. Apply rate limiting to `/stripe/checkout` endpoint
  4. Configure appropriate limits (e.g., 10 requests per minute)
- **Priority**: High
- **Estimated Time**: 45 minutes

### Task 6: Implement Webhook Security - [x] COMPLETED
- **File**: `apps/api/app/services/stripe_service.py`
- **Action**: Add Stripe webhook signature verification
- **Steps**:
  1. Create webhook verification method
  2. Add webhook secret to environment configuration
  3. Implement signature verification using `stripe.Webhook.construct_event()`
  4. Add webhook endpoint to router
- **Priority**: High
- **Estimated Time**: 60 minutes

### Task 7: Add Structured Logging - [x] COMPLETED
- **File**: `apps/api/main.py` and service files
- **Action**: Implement proper logging throughout the application
- **Steps**:
  1. Configure logging in `main.py`
  2. Add logger instances to service files
  3. Add structured logging to key operations
  4. Include request/response logging middleware
- **Priority**: High
- **Estimated Time**: 45 minutes

### Task 8: Improve Error Handling - [x] COMPLETED
- **File**: `apps/api/app/routers/stripe.py`
- **Action**: Improve error message specificity
- **Steps**:
  1. Fix line 25 generic error message
  2. Add specific error types for different failure scenarios
  3. Log detailed error information while returning safe user messages
  4. Add error tracking/monitoring
- **Priority**: High
- **Estimated Time**: 30 minutes

## 🔵 MEDIUM PRIORITY - Recommended Improvements

### Task 9: Add API Documentation
- **File**: `apps/api/app/models/stripe.py`
- **Action**: Enhance API documentation
- **Steps**:
  1. Add field descriptions to Pydantic models
  2. Add example values for OpenAPI documentation
  3. Update router docstrings with detailed descriptions
  4. Add response examples
- **Priority**: Medium
- **Estimated Time**: 30 minutes

### Task 10: Environment Variable Validation
- **File**: `apps/api/app/config.py`
- **Action**: Add startup validation for required environment variables
- **Steps**:
  1. Add validation for required fields
  2. Add helpful error messages for missing configuration
  3. Implement configuration validation on startup
  4. Add URL format validation
- **Priority**: Medium
- **Estimated Time**: 25 minutes

### Task 11: Add Health Check Enhancements
- **File**: `apps/api/main.py`
- **Action**: Enhance health check endpoint
- **Steps**:
  1. Add dependency health checks (Stripe API, database connection)
  2. Add version information
  3. Add detailed health status responses
  4. Add readiness vs liveness endpoints
- **Priority**: Medium
- **Estimated Time**: 40 minutes

### Task 12: Add Request/Response Logging
- **File**: `apps/api/main.py`
- **Action**: Add middleware for request/response logging
- **Steps**:
  1. Create logging middleware
  2. Log request details (method, path, user agent)
  3. Log response status and timing
  4. Exclude sensitive data from logs
- **Priority**: Medium
- **Estimated Time**: 35 minutes

## 🟢 LOW PRIORITY - Future Enhancements

### Task 13: Add Test Suite
- **File**: `apps/api/tests/` (new directory)
- **Action**: Create comprehensive test suite
- **Steps**:
  1. Create test directory structure
  2. Add unit tests for services
  3. Add integration tests for API endpoints
  4. Add test configuration and fixtures
- **Priority**: Low
- **Estimated Time**: 3 hours

### Task 14: Add Authentication Integration
- **File**: `apps/api/app/` (various files)
- **Action**: Integrate with existing Clerk authentication
- **Steps**:
  1. Add Clerk JWT verification
  2. Create authentication middleware
  3. Protect endpoints with authentication
  4. Add user context to requests
- **Priority**: Low
- **Estimated Time**: 2 hours

### Task 15: Add API Versioning
- **File**: `apps/api/main.py` and router files
- **Action**: Implement API versioning strategy
- **Steps**:
  1. Add version prefix to routes
  2. Create versioned router structure
  3. Add version headers
  4. Document versioning strategy
- **Priority**: Low
- **Estimated Time**: 1 hour

### Task 16: Add Monitoring and Metrics
- **File**: `apps/api/main.py`
- **Action**: Add application monitoring
- **Steps**:
  1. Add Prometheus metrics endpoint
  2. Add custom metrics for business logic
  3. Add performance monitoring
  4. Add error tracking integration
- **Priority**: Low
- **Estimated Time**: 2 hours

## 🔧 CLEANUP TASKS

### Task 17: Remove Test Endpoint
- **File**: `apps/api/app/routers/stripe.py`
- **Action**: Remove or secure test endpoint
- **Steps**:
  1. Remove `/stripe/test` endpoint or add authentication
  2. Ensure no test code remains in production
- **Priority**: Medium
- **Estimated Time**: 5 minutes

### Task 18: Add Missing .gitignore
- **File**: `apps/api/.gitignore`
- **Action**: Add proper .gitignore for Python API
- **Steps**:
  1. Create `.gitignore` file in `apps/api/`
  2. Add Python-specific ignores
  3. Add environment and IDE ignores
- **Priority**: Medium
- **Estimated Time**: 10 minutes

### Task 19: Update Documentation
- **File**: `apps/api/README.md`
- **Action**: Update documentation with resolved issues
- **Steps**:
  1. Update setup instructions
  2. Add troubleshooting section
  3. Update API documentation
  4. Add security considerations
- **Priority**: Medium
- **Estimated Time**: 20 minutes

## Summary

**Total Critical Tasks**: 4 (1 hour 15 minutes)
**Total High Priority Tasks**: 4 (3 hours)
**Total Medium Priority Tasks**: 6 (2 hours 40 minutes)
**Total Low Priority Tasks**: 4 (8 hours)
**Total Cleanup Tasks**: 3 (35 minutes)

**Estimated Total Time**: 15 hours 30 minutes

## Completion Order Recommendation

1. **Phase 1 (Critical)**: Tasks 1-4 (Must complete before merge)
2. **Phase 2 (High Priority)**: Tasks 5-8 (Should complete before production)
3. **Phase 3 (Medium Priority)**: Tasks 9-12, 17-19 (Quality improvements)
4. **Phase 4 (Low Priority)**: Tasks 13-16 (Future enhancements)