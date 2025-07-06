# RemitMatch API

FastAPI backend for RemitMatch - a web application that streamlines the reconciliation of remittance advice PDFs with invoice data from accounting software.

## Setup

### Prerequisites
- Python 3.8+
- Virtual environment

### Installation

1. Create and activate virtual environment:
```bash
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Configure environment variables:
```bash
cp .env.example .env
# Edit .env with your actual values
```

### Running the API

```bash
python run.py
```

The API will be available at `http://localhost:8001`

## API Endpoints

### Health Check
- **GET** `/health`
- Returns the health status and environment

**Response:**
```json
{
  "status": "healthy",
  "environment": "development"
}
```

### Root
- **GET** `/`
- Returns basic API information

**Response:**
```json
{
  "message": "RemitMatch API is running"
}
```

### Stripe Checkout

#### Create Checkout Session
- **POST** `/stripe/checkout`
- Creates a Stripe checkout session for subscription or one-time payment

**Request Body:**
```json
{
  "user_id": "string",
  "email": "string",
  "price_id": "string",
  "subscription": boolean
}
```

**Response:**
```json
{
  "session_id": "cs_test_..."
}
```

**Error Response:**
```json
{
  "error": "Error message"
}
```

#### Test Stripe Router
- **GET** `/stripe/test`
- Simple test endpoint for Stripe router

**Response:**
```json
{
  "message": "Stripe router is working"
}
```

## Project Structure

```
apps/api/
├── app/
│   ├── __init__.py
│   ├── config.py          # Settings and configuration
│   ├── models/
│   │   ├── __init__.py
│   │   └── stripe.py      # Stripe Pydantic models
│   ├── routers/
│   │   ├── __init__.py
│   │   └── stripe.py      # Stripe API routes
│   ├── services/
│   │   ├── __init__.py
│   │   └── stripe_service.py  # Stripe business logic
│   └── utils/
│       └── __init__.py
├── main.py                # FastAPI application
├── run.py                 # Development server
├── requirements.txt       # Python dependencies
├── .env                   # Environment variables (not in git)
├── .env.example          # Environment template
└── venv/                 # Virtual environment
```

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `API_HOST` | API host address | No (default: 0.0.0.0) |
| `API_PORT` | API port number | No (default: 8001) |
| `API_ENV` | Environment (development/production) | No (default: development) |
| `STRIPE_SECRET_KEY` | Stripe secret key | Yes |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook secret | Yes |
| `FRONTEND_URL` | Frontend URL for CORS | No (default: http://localhost:3000) |
| `SUPABASE_URL` | Supabase project URL | No (for Phase 2) |
| `SUPABASE_SERVICE_KEY` | Supabase service key | No (for Phase 2) |

## Development

The API uses:
- **FastAPI** - Modern Python web framework
- **Pydantic** - Data validation and settings management
- **Stripe** - Payment processing
- **Uvicorn** - ASGI server

## CORS Configuration

The API is configured to allow requests from the frontend URL specified in `FRONTEND_URL` environment variable.