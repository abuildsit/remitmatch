-- RemitMatch Database Schema Migration
-- This migration adds all RemitMatch-specific tables while preserving existing SaaS infrastructure

-- ============================================================================
-- CORE REMITMATCH TABLES
-- ============================================================================

-- Users (enhanced from existing structure)
CREATE TABLE IF NOT EXISTS public.users_remitmatch (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Organisations
CREATE TABLE IF NOT EXISTS public.organisations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  xero_tenant_id TEXT UNIQUE, -- From Xero OAuth connection
  created_by UUID REFERENCES public.users_remitmatch(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Organisation Members
CREATE TABLE IF NOT EXISTS public.organisation_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users_remitmatch(id) ON DELETE CASCADE,
  organisation_id UUID REFERENCES public.organisations(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'user', 'auditor')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, organisation_id)
);

-- Subscriptions (enhanced for organisations)
CREATE TABLE IF NOT EXISTS public.org_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id UUID UNIQUE REFERENCES public.organisations(id) ON DELETE CASCADE,
  stripe_customer_id TEXT NOT NULL,
  stripe_subscription_id TEXT NOT NULL,
  status TEXT NOT NULL,
  tier TEXT NOT NULL CHECK (tier IN ('free', 'business', 'pro', 'max')),
  current_period_start TIMESTAMP WITH TIME ZONE,
  current_period_end TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Xero Integrations
CREATE TABLE IF NOT EXISTS public.xero_integrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id UUID UNIQUE REFERENCES public.organisations(id) ON DELETE CASCADE,
  xero_tenant_id TEXT NOT NULL,
  access_token TEXT NOT NULL,
  refresh_token TEXT NOT NULL,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  token_set JSONB, -- Store full token response
  connected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_sync_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Bank Accounts (from Xero Chart of Accounts)
CREATE TABLE IF NOT EXISTS public.bank_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id UUID REFERENCES public.organisations(id) ON DELETE CASCADE,
  xero_account_id TEXT NOT NULL,
  account_name TEXT NOT NULL,
  account_code TEXT,
  account_type TEXT,
  is_default BOOLEAN DEFAULT FALSE,
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(organisation_id, xero_account_id)
);

-- Xero Invoices (synced from Xero accounting software)
CREATE TABLE IF NOT EXISTS public.xero_invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id UUID REFERENCES public.organisations(id) ON DELETE CASCADE,
  xero_invoice_id TEXT NOT NULL,
  invoice_number TEXT,
  contact_name TEXT,
  total_amount NUMERIC(15,2),
  amount_due NUMERIC(15,2),
  currency TEXT DEFAULT 'AUD',
  status TEXT,
  issue_date DATE,
  due_date DATE,
  xero_updated_date TIMESTAMP WITH TIME ZONE,
  last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE (organisation_id, xero_invoice_id)
);

-- Remittances
CREATE TABLE IF NOT EXISTS public.remittances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id UUID REFERENCES public.organisations(id) ON DELETE CASCADE,
  uploaded_by UUID REFERENCES public.users_remitmatch(id),
  
  -- Status matching RemitMatch spec exactly
  status TEXT NOT NULL CHECK (status IN (
    'Uploaded',
    'Data Retrieved', 
    'All payments matched - Awaiting Approval',
    'Error - Payments Unmatched',
    'Exported to Xero - Unreconciled',
    'Exported to Xero - Reconciled',
    'Export Failed',
    'Soft Deleted'
  )) DEFAULT 'Uploaded',
  
  -- Payment details
  payment_date DATE,
  payment_amount NUMERIC(15,2),
  payment_reference TEXT,
  
  -- AI extraction metadata
  confidence_score NUMERIC(5,2), -- 0-100 confidence percentage
  ai_extracted_data JSONB, -- Store raw AI output
  
  -- Workflow tracking
  approved_at TIMESTAMP WITH TIME ZONE,
  approved_by UUID REFERENCES public.users_remitmatch(id),
  exported_at TIMESTAMP WITH TIME ZONE,
  xero_payment_id TEXT, -- Track Xero payment ID for unapproval
  
  -- Soft delete
  deleted_at TIMESTAMP WITH TIME ZONE,
  deleted_by UUID REFERENCES public.users_remitmatch(id),
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Files (remittance attachments)
CREATE TABLE IF NOT EXISTS public.files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id UUID REFERENCES public.organisations(id) ON DELETE CASCADE,
  remittance_id UUID REFERENCES public.remittances(id) ON DELETE CASCADE,
  storage_path TEXT UNIQUE NOT NULL, -- Supabase storage path
  original_filename TEXT NOT NULL,
  file_size INTEGER,
  mime_type TEXT,
  uploaded_by UUID REFERENCES public.users_remitmatch(id),
  uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Remittance Lines (individual invoice payments within a remittance)
CREATE TABLE IF NOT EXISTS public.remittance_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  remittance_id UUID REFERENCES public.remittances(id) ON DELETE CASCADE,
  
  -- AI extracted values (immutable after extraction)
  invoice_number TEXT NOT NULL,              -- Extracted from AI
  ai_paid_amount NUMERIC(15,2) NOT NULL,     -- From AI extraction
  ai_invoice_id UUID REFERENCES public.xero_invoices(id), -- Matched by backend logic
  
  -- Manual override values (user can modify these)
  manual_paid_amount NUMERIC(15,2),          -- Optional user override
  override_invoice_id UUID REFERENCES public.xero_invoices(id), -- Set by user manually
  
  -- Computed fields (derived from above)
  final_paid_amount NUMERIC(15,2) GENERATED ALWAYS AS (
    COALESCE(manual_paid_amount, ai_paid_amount)
  ) STORED,
  final_invoice_id UUID GENERATED ALWAYS AS (
    COALESCE(override_invoice_id, ai_invoice_id)
  ) STORED,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Audit Log (comprehensive change tracking)
CREATE TABLE IF NOT EXISTS public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  remittance_id UUID REFERENCES public.remittances(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users_remitmatch(id),
  
  -- Action details
  action_type TEXT NOT NULL CHECK (action_type IN (
    'upload', 'ai_extraction', 'manual_edit', 'approval', 'unapproval', 
    'xero_export', 'xero_sync', 'soft_delete', 'restore', 'retry'
  )),
  
  -- Field-level changes
  field_name TEXT,
  old_value TEXT,
  new_value TEXT,
  
  -- Outcome tracking
  outcome TEXT CHECK (outcome IN ('success', 'error', 'warning')),
  error_message TEXT,
  reason TEXT,
  
  -- Context
  ip_address INET,
  user_agent TEXT,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Usage Tracking (for subscription limits)
CREATE TABLE IF NOT EXISTS public.usage_tracking (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id UUID REFERENCES public.organisations(id) ON DELETE CASCADE,
  month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
  year INTEGER NOT NULL CHECK (year >= 2024),
  remittances_processed INTEGER DEFAULT 0,
  ai_extractions_count INTEGER DEFAULT 0,
  storage_used_bytes BIGINT DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(organisation_id, month, year)
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Core lookup indexes
CREATE INDEX IF NOT EXISTS idx_organisations_xero_tenant ON public.organisations(xero_tenant_id);
CREATE INDEX IF NOT EXISTS idx_org_members_user_org ON public.organisation_members(user_id, organisation_id);
CREATE INDEX IF NOT EXISTS idx_org_members_org_role ON public.organisation_members(organisation_id, role);

-- Remittance indexes
CREATE INDEX IF NOT EXISTS idx_remittances_org_status ON public.remittances(organisation_id, status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_remittances_org_created ON public.remittances(organisation_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_remittances_uploaded_by ON public.remittances(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_remittances_xero_payment ON public.remittances(xero_payment_id) WHERE xero_payment_id IS NOT NULL;

-- Xero Invoice indexes
CREATE INDEX IF NOT EXISTS idx_xero_invoices_org_xero ON public.xero_invoices(organisation_id, xero_invoice_id);
CREATE INDEX IF NOT EXISTS idx_xero_invoices_org_number ON public.xero_invoices(organisation_id, invoice_number);
CREATE INDEX IF NOT EXISTS idx_xero_invoices_org_status ON public.xero_invoices(organisation_id, status);

-- Remittance lines indexes
CREATE INDEX IF NOT EXISTS idx_remittance_lines_remittance ON public.remittance_lines(remittance_id);
CREATE INDEX IF NOT EXISTS idx_remittance_lines_ai_invoice ON public.remittance_lines(ai_invoice_id);
CREATE INDEX IF NOT EXISTS idx_remittance_lines_override_invoice ON public.remittance_lines(override_invoice_id);

-- Audit log indexes
CREATE INDEX IF NOT EXISTS idx_audit_log_remittance_created ON public.audit_log(remittance_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_user_created ON public.audit_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_action_created ON public.audit_log(action_type, created_at DESC);

-- Files indexes
CREATE INDEX IF NOT EXISTS idx_files_remittance ON public.files(remittance_id);
CREATE INDEX IF NOT EXISTS idx_files_org_uploaded ON public.files(organisation_id, uploaded_at DESC);

-- Usage tracking indexes
CREATE INDEX IF NOT EXISTS idx_usage_tracking_org_period ON public.usage_tracking(organisation_id, year, month);

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.users_remitmatch ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organisations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organisation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.xero_integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.xero_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remittances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remittance_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usage_tracking ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- Users can see their own profile
CREATE POLICY "Users can view own profile" ON public.users_remitmatch
  FOR SELECT USING (auth.uid()::text = id::text);

CREATE POLICY "Users can update own profile" ON public.users_remitmatch
  FOR UPDATE USING (auth.uid()::text = id::text);

-- Organisation access through membership
CREATE POLICY "Users can view organisations they belong to" ON public.organisations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members 
      WHERE organisation_id = organisations.id 
      AND user_id::text = auth.uid()::text
    )
  );

-- Organisation members can see other members of same org
CREATE POLICY "Members can view organisation members" ON public.organisation_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members om
      WHERE om.organisation_id = organisation_members.organisation_id
      AND om.user_id::text = auth.uid()::text
    )
  );

-- Only owners and admins can manage members
CREATE POLICY "Owners and admins can manage members" ON public.organisation_members
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members om
      WHERE om.organisation_id = organisation_members.organisation_id
      AND om.user_id::text = auth.uid()::text
      AND om.role IN ('owner', 'admin')
    )
  );

-- Organisation-scoped data access
CREATE POLICY "Users can access organisation subscriptions" ON public.org_subscriptions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members 
      WHERE organisation_id = org_subscriptions.organisation_id 
      AND user_id::text = auth.uid()::text
    )
  );

CREATE POLICY "Users can access organisation Xero integrations" ON public.xero_integrations
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members 
      WHERE organisation_id = xero_integrations.organisation_id 
      AND user_id::text = auth.uid()::text
    )
  );

CREATE POLICY "Users can access organisation bank accounts" ON public.bank_accounts
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members 
      WHERE organisation_id = bank_accounts.organisation_id 
      AND user_id::text = auth.uid()::text
    )
  );

CREATE POLICY "Users can access organisation xero invoices" ON public.xero_invoices
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members 
      WHERE organisation_id = xero_invoices.organisation_id 
      AND user_id::text = auth.uid()::text
    )
  );

-- Remittance access policies
CREATE POLICY "Users can access organisation remittances" ON public.remittances
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members 
      WHERE organisation_id = remittances.organisation_id 
      AND user_id::text = auth.uid()::text
    )
  );

-- Users, admins, and owners can create/update remittances
CREATE POLICY "Users can manage remittances" ON public.remittances
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members 
      WHERE organisation_id = remittances.organisation_id 
      AND user_id::text = auth.uid()::text
      AND role IN ('owner', 'admin', 'user')
    )
  );

-- Auditors can only read
CREATE POLICY "Auditors can view remittances" ON public.remittances
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members 
      WHERE organisation_id = remittances.organisation_id 
      AND user_id::text = auth.uid()::text
      AND role = 'auditor'
    )
  );

-- Files access through remittance
CREATE POLICY "Users can access files through remittance access" ON public.files
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.remittances r
      JOIN public.organisation_members om ON r.organisation_id = om.organisation_id
      WHERE r.id = files.remittance_id
      AND om.user_id::text = auth.uid()::text
    )
  );

-- Remittance lines access through remittance
CREATE POLICY "Users can access remittance lines" ON public.remittance_lines
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.remittances r
      JOIN public.organisation_members om ON r.organisation_id = om.organisation_id
      WHERE r.id = remittance_lines.remittance_id
      AND om.user_id::text = auth.uid()::text
    )
  );

-- Audit log access
CREATE POLICY "Users can view audit logs for accessible remittances" ON public.audit_log
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.remittances r
      JOIN public.organisation_members om ON r.organisation_id = om.organisation_id
      WHERE r.id = audit_log.remittance_id
      AND om.user_id::text = auth.uid()::text
    )
  );

-- Usage tracking (owners and admins only)
CREATE POLICY "Owners and admins can view usage tracking" ON public.usage_tracking
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.organisation_members 
      WHERE organisation_id = usage_tracking.organisation_id 
      AND user_id::text = auth.uid()::text
      AND role IN ('owner', 'admin')
    )
  );

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Add updated_at triggers
CREATE TRIGGER update_users_remitmatch_updated_at BEFORE UPDATE ON public.users_remitmatch FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_organisations_updated_at BEFORE UPDATE ON public.organisations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_organisation_members_updated_at BEFORE UPDATE ON public.organisation_members FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_org_subscriptions_updated_at BEFORE UPDATE ON public.org_subscriptions FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_xero_integrations_updated_at BEFORE UPDATE ON public.xero_integrations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_bank_accounts_updated_at BEFORE UPDATE ON public.bank_accounts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_xero_invoices_updated_at BEFORE UPDATE ON public.xero_invoices FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_remittances_updated_at BEFORE UPDATE ON public.remittances FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_remittance_lines_updated_at BEFORE UPDATE ON public.remittance_lines FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_usage_tracking_updated_at BEFORE UPDATE ON public.usage_tracking FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE public.organisations IS 'Top-level tenant organisations in RemitMatch. Each org has its own Xero connection.';
COMMENT ON TABLE public.organisation_members IS 'Many-to-many relationship between users and organisations with role-based access.';
COMMENT ON TABLE public.remittances IS 'Core remittance documents with full workflow state tracking.';
COMMENT ON TABLE public.remittance_lines IS 'Individual invoice payments within a remittance, supporting AI extraction and manual overrides.';
COMMENT ON TABLE public.audit_log IS 'Comprehensive audit trail of all remittance-related actions.';
COMMENT ON TABLE public.usage_tracking IS 'Monthly usage statistics for subscription limit enforcement.';

COMMENT ON COLUMN public.remittances.status IS 'Workflow status matching RemitMatch specification exactly.';
COMMENT ON COLUMN public.remittance_lines.final_paid_amount IS 'Computed column: manual override if present, otherwise AI extracted amount.';
COMMENT ON COLUMN public.remittance_lines.final_invoice_id IS 'Computed column: manual override if present, otherwise AI matched invoice.';