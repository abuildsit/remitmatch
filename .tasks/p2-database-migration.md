# Phase 2: Database Migration

## Overview
This phase migrates the existing Prisma-defined schema to Supabase, adds RemitMatch-specific tables, and integrates the database with FastAPI. The Prisma schema files are retained as documentation.

## Prerequisites
- Phase 1 completed (FastAPI backend running)
- Node.js and npm installed
- Docker installed (for Supabase local development)
- Existing Prisma schema available for reference

## Phase 2.1: Local Supabase Setup

### Objective
Set up a local Supabase instance for development and prepare the migration environment.

### Tasks
- [ ] Install Supabase CLI globally:
  ```bash
  npm install -g supabase
  ```
- [ ] Initialize Supabase in project root:
  ```bash
  supabase init
  ```
- [ ] Configure `supabase/config.toml`:
  ```toml
  # Update the project_id to something meaningful
  project_id = "remitmatch-local"
  
  [api]
  port = 54321
  
  [db]
  port = 54322
  
  [studio]
  port = 54323
  ```
- [ ] Start local Supabase:
  ```bash
  supabase start
  ```
- [ ] Save the output credentials to a temporary file (includes URLs and keys)
- [ ] Create `supabase/.env.local`:
  ```
  SUPABASE_URL=http://localhost:54321
  SUPABASE_ANON_KEY=<anon key from output>
  SUPABASE_SERVICE_KEY=<service key from output>
  DB_URL=postgresql://postgres:postgres@localhost:54322/postgres
  ```
- [ ] Update `apps/web/.env.local` with Supabase credentials:
  ```
  NEXT_PUBLIC_SUPABASE_URL=http://localhost:54321
  NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>
  SUPABASE_URL=http://localhost:54321
  SUPABASE_SERVICE_KEY=<service key>
  ```
- [ ] Update `apps/api/.env` with Supabase credentials:
  ```
  SUPABASE_URL=http://localhost:54321
  SUPABASE_SERVICE_KEY=<service key>
  ```
- [ ] Verify Supabase Studio is accessible at http://localhost:54323
- [ ] Test connection with:
  ```bash
  supabase db dump
  ```

## Phase 2.2: Migrate Existing Schema

### Objective
Convert the existing Prisma schema to Supabase SQL migrations while preserving the current data structure.

### Tasks
- [ ] Create migration directory structure:
  ```bash
  mkdir -p supabase/migrations
  ```
- [ ] Create `supabase/migrations/20240101000001_initial_schema.sql`:
  ```sql
  -- Enable UUID extension
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  
  -- User table (matching Prisma schema)
  CREATE TABLE IF NOT EXISTS "user" (
    id SERIAL PRIMARY KEY,
    created_time TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    email TEXT UNIQUE NOT NULL,
    first_name TEXT,
    last_name TEXT,
    gender TEXT,
    profile_image_url TEXT,
    user_id TEXT UNIQUE NOT NULL,
    subscription TEXT
  );
  
  -- Create index on user_id for faster lookups
  CREATE INDEX idx_user_user_id ON "user"(user_id);
  CREATE INDEX idx_user_email ON "user"(email);
  
  -- Payments table
  CREATE TABLE IF NOT EXISTS payments (
    id SERIAL PRIMARY KEY,
    created_time TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    stripe_id TEXT NOT NULL,
    email TEXT NOT NULL,
    amount TEXT NOT NULL,
    payment_time TEXT NOT NULL,
    payment_date TEXT NOT NULL,
    currency TEXT NOT NULL,
    user_id TEXT NOT NULL,
    customer_details TEXT NOT NULL,
    payment_intent TEXT NOT NULL
  );
  
  -- Create indexes for payments
  CREATE INDEX idx_payments_user_id ON payments(user_id);
  CREATE INDEX idx_payments_stripe_id ON payments(stripe_id);
  
  -- Subscriptions table
  CREATE TABLE IF NOT EXISTS subscriptions (
    id SERIAL PRIMARY KEY,
    created_time TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    subscription_id TEXT NOT NULL,
    stripe_user_id TEXT NOT NULL,
    status TEXT NOT NULL,
    start_date TEXT NOT NULL,
    end_date TEXT,
    plan_id TEXT NOT NULL,
    default_payment_method_id TEXT,
    email TEXT NOT NULL,
    user_id TEXT NOT NULL
  );
  
  -- Create indexes for subscriptions
  CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
  CREATE INDEX idx_subscriptions_subscription_id ON subscriptions(subscription_id);
  CREATE INDEX idx_subscriptions_status ON subscriptions(status);
  
  -- Subscription plans table
  CREATE TABLE IF NOT EXISTS subscriptions_plans (
    id SERIAL PRIMARY KEY,
    created_time TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    plan_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    amount TEXT NOT NULL,
    currency TEXT NOT NULL,
    interval TEXT NOT NULL
  );
  
  -- Create index for plan lookups
  CREATE INDEX idx_subscriptions_plans_plan_id ON subscriptions_plans(plan_id);
  
  -- Invoices table
  CREATE TABLE IF NOT EXISTS invoices (
    id SERIAL PRIMARY KEY,
    created_time TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    invoice_id TEXT NOT NULL,
    subscription_id TEXT NOT NULL,
    amount_paid TEXT NOT NULL,
    amount_due TEXT,
    currency TEXT NOT NULL,
    status TEXT NOT NULL,
    email TEXT NOT NULL,
    user_id TEXT
  );
  
  -- Create indexes for invoices
  CREATE INDEX idx_invoices_user_id ON invoices(user_id);
  CREATE INDEX idx_invoices_invoice_id ON invoices(invoice_id);
  CREATE INDEX idx_invoices_subscription_id ON invoices(subscription_id);
  ```
- [ ] Apply the migration:
  ```bash
  supabase db push
  ```
- [ ] Verify tables in Supabase Studio
- [ ] Create RLS policies file `supabase/migrations/20240101000002_initial_rls_policies.sql`:
  ```sql
  -- Enable RLS on all tables
  ALTER TABLE "user" ENABLE ROW LEVEL SECURITY;
  ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
  ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
  ALTER TABLE subscriptions_plans ENABLE ROW LEVEL SECURITY;
  ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
  
  -- User table policies
  CREATE POLICY "Users can view their own data" ON "user"
    FOR SELECT USING (auth.uid()::text = user_id);
  
  CREATE POLICY "Users can update their own data" ON "user"
    FOR UPDATE USING (auth.uid()::text = user_id);
  
  -- Payments policies
  CREATE POLICY "Users can view their own payments" ON payments
    FOR SELECT USING (auth.uid()::text = user_id);
  
  -- Subscriptions policies
  CREATE POLICY "Users can view their own subscriptions" ON subscriptions
    FOR SELECT USING (auth.uid()::text = user_id);
  
  -- Subscription plans are public
  CREATE POLICY "Subscription plans are viewable by all" ON subscriptions_plans
    FOR SELECT USING (true);
  
  -- Invoices policies
  CREATE POLICY "Users can view their own invoices" ON invoices
    FOR SELECT USING (auth.uid()::text = user_id);
  
  -- Service role bypass (for backend operations)
  CREATE POLICY "Service role has full access to user" ON "user"
    USING (auth.role() = 'service_role');
  
  CREATE POLICY "Service role has full access to payments" ON payments
    USING (auth.role() = 'service_role');
  
  CREATE POLICY "Service role has full access to subscriptions" ON subscriptions
    USING (auth.role() = 'service_role');
  
  CREATE POLICY "Service role has full access to invoices" ON invoices
    USING (auth.role() = 'service_role');
  ```
- [ ] Apply RLS policies:
  ```bash
  supabase db push
  ```
- [ ] Test existing Next.js app functionality with local Supabase
- [ ] Verify user creation works
- [ ] Verify subscription queries work

## Phase 2.3: Add RemitMatch Tables

### Objective
Create RemitMatch-specific tables with proper relationships and RLS policies for multi-tenant security.

### Tasks
- [ ] Create `supabase/migrations/20240101000003_remitmatch_schema.sql`:
  ```sql
  -- Create enum for remittance status
  CREATE TYPE remittance_status AS ENUM (
    'Uploaded',
    'Data Retrieved',
    'All payments matched - Awaiting Approval',
    'Error - Payments Unmatched',
    'Exported to Xero - Unreconciled',
    'Exported to Xero - Reconciled',
    'Export Failed',
    'Soft Deleted'
  );
  
  -- Create enum for user roles
  CREATE TYPE organisation_role AS ENUM (
    'owner',
    'admin',
    'user',
    'auditor'
  );
  
  -- Organisations table
  CREATE TABLE IF NOT EXISTS organisations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    xero_tenant_id TEXT UNIQUE,
    subscription_tier TEXT DEFAULT 'free',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
  );
  
  -- Organisation members junction table
  CREATE TABLE IF NOT EXISTS organisation_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organisation_id UUID NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    role organisation_role NOT NULL DEFAULT 'user',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    UNIQUE(organisation_id, user_id)
  );
  
  -- Remittances table
  CREATE TABLE IF NOT EXISTS remittances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organisation_id UUID NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
    status remittance_status NOT NULL DEFAULT 'Uploaded',
    payment_date DATE,
    total_amount DECIMAL(10, 2),
    payment_reference TEXT,
    confidence_score DECIMAL(3, 2),
    xero_payment_id TEXT,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    deleted_at TIMESTAMP WITH TIME ZONE
  );
  
  -- Remittance lines table
  CREATE TABLE IF NOT EXISTS remittance_lines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    remittance_id UUID NOT NULL REFERENCES remittances(id) ON DELETE CASCADE,
    invoice_number TEXT NOT NULL,
    ai_paid_amount DECIMAL(10, 2) NOT NULL,
    manual_paid_amount DECIMAL(10, 2),
    ai_invoice_id UUID,
    override_invoice_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
  );
  
  -- Audit logs table
  CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organisation_id UUID NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
    remittance_id UUID REFERENCES remittances(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    action TEXT NOT NULL,
    field_name TEXT,
    old_value TEXT,
    new_value TEXT,
    outcome TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
  );
  
  -- Files table for document storage
  CREATE TABLE IF NOT EXISTS files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organisation_id UUID NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
    remittance_id UUID REFERENCES remittances(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_size INTEGER,
    mime_type TEXT,
    uploaded_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
  );
  
  -- Create indexes for performance
  CREATE INDEX idx_org_members_org_id ON organisation_members(organisation_id);
  CREATE INDEX idx_org_members_user_id ON organisation_members(user_id);
  CREATE INDEX idx_remittances_org_id ON remittances(organisation_id);
  CREATE INDEX idx_remittances_status ON remittances(status);
  CREATE INDEX idx_remittance_lines_remittance_id ON remittance_lines(remittance_id);
  CREATE INDEX idx_audit_logs_org_id ON audit_logs(organisation_id);
  CREATE INDEX idx_audit_logs_remittance_id ON audit_logs(remittance_id);
  CREATE INDEX idx_files_org_id ON files(organisation_id);
  CREATE INDEX idx_files_remittance_id ON files(remittance_id);
  
  -- Add updated_at trigger function
  CREATE OR REPLACE FUNCTION update_updated_at_column()
  RETURNS TRIGGER AS $$
  BEGIN
    NEW.updated_at = TIMEZONE('utc', NOW());
    RETURN NEW;
  END;
  $$ language 'plpgsql';
  
  -- Apply updated_at triggers
  CREATE TRIGGER update_organisations_updated_at BEFORE UPDATE ON organisations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  
  CREATE TRIGGER update_organisation_members_updated_at BEFORE UPDATE ON organisation_members
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  
  CREATE TRIGGER update_remittances_updated_at BEFORE UPDATE ON remittances
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  
  CREATE TRIGGER update_remittance_lines_updated_at BEFORE UPDATE ON remittance_lines
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  ```
- [ ] Apply RemitMatch schema:
  ```bash
  supabase db push
  ```
- [ ] Create RLS policies for RemitMatch tables `supabase/migrations/20240101000004_remitmatch_rls_policies.sql`:
  ```sql
  -- Enable RLS on RemitMatch tables
  ALTER TABLE organisations ENABLE ROW LEVEL SECURITY;
  ALTER TABLE organisation_members ENABLE ROW LEVEL SECURITY;
  ALTER TABLE remittances ENABLE ROW LEVEL SECURITY;
  ALTER TABLE remittance_lines ENABLE ROW LEVEL SECURITY;
  ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
  ALTER TABLE files ENABLE ROW LEVEL SECURITY;
  
  -- Helper function to check organisation membership
  CREATE OR REPLACE FUNCTION is_organisation_member(org_id UUID, user_id TEXT)
  RETURNS BOOLEAN AS $$
  BEGIN
    RETURN EXISTS (
      SELECT 1 FROM organisation_members
      WHERE organisation_id = org_id
      AND organisation_members.user_id = user_id
    );
  END;
  $$ LANGUAGE plpgsql SECURITY DEFINER;
  
  -- Organisations policies
  CREATE POLICY "Users can view their organisations" ON organisations
    FOR SELECT USING (
      is_organisation_member(id, auth.uid()::text)
    );
  
  -- Organisation members policies
  CREATE POLICY "Members can view their organisation members" ON organisation_members
    FOR SELECT USING (
      is_organisation_member(organisation_id, auth.uid()::text)
    );
  
  -- Remittances policies
  CREATE POLICY "Members can view their organisation remittances" ON remittances
    FOR SELECT USING (
      is_organisation_member(organisation_id, auth.uid()::text)
      AND deleted_at IS NULL
    );
  
  -- Remittance lines policies
  CREATE POLICY "Members can view remittance lines" ON remittance_lines
    FOR SELECT USING (
      EXISTS (
        SELECT 1 FROM remittances
        WHERE remittances.id = remittance_lines.remittance_id
        AND is_organisation_member(remittances.organisation_id, auth.uid()::text)
      )
    );
  
  -- Audit logs policies
  CREATE POLICY "Members can view audit logs" ON audit_logs
    FOR SELECT USING (
      is_organisation_member(organisation_id, auth.uid()::text)
    );
  
  -- Files policies
  CREATE POLICY "Members can view files" ON files
    FOR SELECT USING (
      is_organisation_member(organisation_id, auth.uid()::text)
    );
  
  -- Service role policies for all tables
  CREATE POLICY "Service role full access to organisations" ON organisations
    USING (auth.role() = 'service_role');
  
  CREATE POLICY "Service role full access to organisation_members" ON organisation_members
    USING (auth.role() = 'service_role');
  
  CREATE POLICY "Service role full access to remittances" ON remittances
    USING (auth.role() = 'service_role');
  
  CREATE POLICY "Service role full access to remittance_lines" ON remittance_lines
    USING (auth.role() = 'service_role');
  
  CREATE POLICY "Service role full access to audit_logs" ON audit_logs
    USING (auth.role() = 'service_role');
  
  CREATE POLICY "Service role full access to files" ON files
    USING (auth.role() = 'service_role');
  ```
- [ ] Apply RLS policies:
  ```bash
  supabase db push
  ```
- [ ] Configure Supabase Storage bucket:
  ```bash
  # Create storage bucket via SQL
  supabase sql -f - <<EOF
  INSERT INTO storage.buckets (id, name, public)
  VALUES ('remittance-files', 'remittance-files', false);
  EOF
  ```
- [ ] Create storage policies file `supabase/migrations/20240101000005_storage_policies.sql`:
  ```sql
  -- Storage policies for remittance files
  CREATE POLICY "Organisation members can upload files" ON storage.objects
    FOR INSERT WITH CHECK (
      bucket_id = 'remittance-files' AND
      (storage.foldername(name))[1]::uuid IN (
        SELECT organisation_id FROM organisation_members
        WHERE user_id = auth.uid()::text
      )
    );
  
  CREATE POLICY "Organisation members can view files" ON storage.objects
    FOR SELECT USING (
      bucket_id = 'remittance-files' AND
      (storage.foldername(name))[1]::uuid IN (
        SELECT organisation_id FROM organisation_members
        WHERE user_id = auth.uid()::text
      )
    );
  
  CREATE POLICY "Organisation members can delete files" ON storage.objects
    FOR DELETE USING (
      bucket_id = 'remittance-files' AND
      (storage.foldername(name))[1]::uuid IN (
        SELECT organisation_id FROM organisation_members
        WHERE user_id = auth.uid()::text
      )
    );
  ```
- [ ] Verify all tables and policies in Supabase Studio

## Phase 2.4: FastAPI Database Integration

### Objective
Connect FastAPI to Supabase and create database models and utilities.

### Tasks
- [ ] Update `apps/api/requirements.txt` to ensure supabase is included
- [ ] Create `apps/api/app/database.py`:
  ```python
  from supabase import create_client, Client
  from app.config import settings
  from typing import Optional
  import logging
  
  logger = logging.getLogger(__name__)
  
  class Database:
      _instance: Optional[Client] = None
      
      @classmethod
      def get_client(cls) -> Client:
          """Get or create Supabase client singleton"""
          if cls._instance is None:
              if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_KEY:
                  raise ValueError("Supabase credentials not configured")
              
              cls._instance = create_client(
                  settings.SUPABASE_URL,
                  settings.SUPABASE_SERVICE_KEY
              )
              logger.info("Supabase client initialized")
          
          return cls._instance
  
  # Convenience function
  def get_db() -> Client:
      """Get Supabase client instance"""
      return Database.get_client()
  ```
- [ ] Create `apps/api/app/models/database.py` for Pydantic models:
  ```python
  from pydantic import BaseModel
  from typing import Optional, List
  from datetime import datetime
  from enum import Enum
  import uuid
  
  # Enums matching database
  class RemittanceStatus(str, Enum):
      UPLOADED = "Uploaded"
      DATA_RETRIEVED = "Data Retrieved"
      ALL_MATCHED_AWAITING = "All payments matched - Awaiting Approval"
      ERROR_UNMATCHED = "Error - Payments Unmatched"
      EXPORTED_UNRECONCILED = "Exported to Xero - Unreconciled"
      EXPORTED_RECONCILED = "Exported to Xero - Reconciled"
      EXPORT_FAILED = "Export Failed"
      SOFT_DELETED = "Soft Deleted"
  
  class OrganisationRole(str, Enum):
      OWNER = "owner"
      ADMIN = "admin"
      USER = "user"
      AUDITOR = "auditor"
  
  # Database models
  class Organisation(BaseModel):
      id: uuid.UUID
      name: str
      xero_tenant_id: Optional[str]
      subscription_tier: str = "free"
      created_at: datetime
      updated_at: datetime
  
  class OrganisationMember(BaseModel):
      id: uuid.UUID
      organisation_id: uuid.UUID
      user_id: str
      role: OrganisationRole
      created_at: datetime
      updated_at: datetime
  
  class Remittance(BaseModel):
      id: uuid.UUID
      organisation_id: uuid.UUID
      status: RemittanceStatus
      payment_date: Optional[datetime]
      total_amount: Optional[float]
      payment_reference: Optional[str]
      confidence_score: Optional[float]
      xero_payment_id: Optional[str]
      created_by: str
      created_at: datetime
      updated_at: datetime
      deleted_at: Optional[datetime]
  
  class RemittanceLine(BaseModel):
      id: uuid.UUID
      remittance_id: uuid.UUID
      invoice_number: str
      ai_paid_amount: float
      manual_paid_amount: Optional[float]
      ai_invoice_id: Optional[uuid.UUID]
      override_invoice_id: Optional[uuid.UUID]
      created_at: datetime
      updated_at: datetime
  
  class AuditLog(BaseModel):
      id: uuid.UUID
      organisation_id: uuid.UUID
      remittance_id: Optional[uuid.UUID]
      user_id: str
      action: str
      field_name: Optional[str]
      old_value: Optional[str]
      new_value: Optional[str]
      outcome: Optional[str]
      created_at: datetime
  ```
- [ ] Create `apps/api/app/utils/database_helpers.py`:
  ```python
  from typing import Dict, Any, Optional
  from app.database import get_db
  import logging
  
  logger = logging.getLogger(__name__)
  
  async def check_organisation_access(user_id: str, organisation_id: str) -> bool:
      """Check if user has access to organisation"""
      try:
          db = get_db()
          result = db.table('organisation_members').select('*').eq(
              'user_id', user_id
          ).eq(
              'organisation_id', organisation_id
          ).execute()
          
          return len(result.data) > 0
      except Exception as e:
          logger.error(f"Error checking organisation access: {e}")
          return False
  
  async def create_audit_log(
      organisation_id: str,
      user_id: str,
      action: str,
      remittance_id: Optional[str] = None,
      field_name: Optional[str] = None,
      old_value: Optional[str] = None,
      new_value: Optional[str] = None,
      outcome: Optional[str] = None
  ) -> Dict[str, Any]:
      """Create an audit log entry"""
      try:
          db = get_db()
          data = {
              'organisation_id': organisation_id,
              'user_id': user_id,
              'action': action,
              'remittance_id': remittance_id,
              'field_name': field_name,
              'old_value': old_value,
              'new_value': new_value,
              'outcome': outcome
          }
          
          result = db.table('audit_logs').insert(data).execute()
          return result.data[0] if result.data else {}
      except Exception as e:
          logger.error(f"Error creating audit log: {e}")
          raise
  ```
- [ ] Create database health check endpoint in `apps/api/main.py`:
  ```python
  from app.database import get_db
  
  @app.get("/health/db")
  async def database_health():
      """Check database connectivity"""
      try:
          db = get_db()
          # Try to query a simple table
          result = db.table('subscriptions_plans').select('count').execute()
          return {
              "status": "healthy",
              "database": "connected",
              "message": "Database connection successful"
          }
      except Exception as e:
          return {
              "status": "unhealthy",
              "database": "disconnected",
              "error": str(e)
          }
  ```
- [ ] Test database connection:
  ```bash
  curl http://localhost:8000/health/db
  ```
- [ ] Create test endpoint to verify RLS in `apps/api/app/routers/test.py`:
  ```python
  from fastapi import APIRouter, Header, HTTPException
  from app.database import get_db
  from typing import Optional
  
  router = APIRouter()
  
  @router.get("/organisations")
  async def get_user_organisations(user_id: Optional[str] = Header(None)):
      """Test endpoint to get user's organisations"""
      if not user_id:
          raise HTTPException(status_code=400, detail="user_id header required")
      
      try:
          db = get_db()
          # Get organisations where user is a member
          result = db.table('organisation_members').select(
              'organisation_id, role, organisations(id, name, subscription_tier)'
          ).eq('user_id', user_id).execute()
          
          return {"organisations": result.data}
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  ```
- [ ] Add test router to main.py:
  ```python
  from app.routers import stripe, test
  
  app.include_router(test.router, prefix="/test", tags=["test"])
  ```
- [ ] Test the endpoint with a test user_id
- [ ] Document database schema in `apps/api/docs/database.md`
- [ ] Commit Phase 2 changes

## Verification Checklist
- [ ] Local Supabase is running
- [ ] Supabase Studio accessible at http://localhost:54323
- [ ] All tables created successfully
- [ ] RLS policies are in place
- [ ] Storage bucket configured
- [ ] FastAPI can connect to database
- [ ] Database health check returns healthy
- [ ] Test endpoint can query organisations
- [ ] Existing Next.js functionality still works

## Next Steps
Once Phase 2 is complete, proceed to Phase 3: State Management & Authentication, which will implement Zustand for session management and integrate Xero OAuth.