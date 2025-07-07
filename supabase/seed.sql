-- RemitMatch Test Seed Data
-- This file creates realistic test data to validate the database schema

-- Insert test users
INSERT INTO public.users_remitmatch (id, email, full_name) VALUES
  ('11111111-1111-1111-1111-111111111111', 'john.owner@acme.com', 'John Smith'),
  ('22222222-2222-2222-2222-222222222222', 'jane.admin@acme.com', 'Jane Doe'),
  ('33333333-3333-3333-3333-333333333333', 'bob.user@acme.com', 'Bob Johnson'),
  ('44444444-4444-4444-4444-444444444444', 'alice.auditor@acme.com', 'Alice Brown'),
  ('55555555-5555-5555-5555-555555555555', 'tom.owner@techcorp.com', 'Tom Wilson');

-- Insert test organisations
INSERT INTO public.organisations (id, name, xero_tenant_id, created_by) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'ACME Corporation', 'acme-xero-tenant-123', '11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'TechCorp Ltd', 'techcorp-xero-tenant-456', '55555555-5555-5555-5555-555555555555');

-- Insert organisation members with different roles
INSERT INTO public.organisation_members (user_id, organisation_id, role) VALUES
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'owner'),
  ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'admin'),
  ('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'user'),
  ('44444444-4444-4444-4444-444444444444', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'auditor'),
  ('55555555-5555-5555-5555-555555555555', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'owner');

-- Insert subscription data
INSERT INTO public.org_subscriptions (organisation_id, stripe_customer_id, stripe_subscription_id, status, tier, current_period_end) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cus_acme123', 'sub_acme123', 'active', 'business', NOW() + INTERVAL '30 days'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'cus_tech456', 'sub_tech456', 'active', 'pro', NOW() + INTERVAL '30 days');

-- Insert Xero integration data
INSERT INTO public.xero_integrations (organisation_id, xero_tenant_id, access_token, refresh_token, expires_at) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'acme-xero-tenant-123', 'xero_access_token_123', 'xero_refresh_token_123', NOW() + INTERVAL '30 minutes'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'techcorp-xero-tenant-456', 'xero_access_token_456', 'xero_refresh_token_456', NOW() + INTERVAL '30 minutes');

-- Insert bank accounts
INSERT INTO public.bank_accounts (organisation_id, xero_account_id, account_name, account_code, is_default) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bank-001', 'ACME Main Account', '1000', true),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bank-002', 'ACME Savings Account', '1001', false),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bank-003', 'TechCorp Operating Account', '2000', true);

-- Insert test invoices from Xero
INSERT INTO public.xero_invoices (id, organisation_id, xero_invoice_id, invoice_number, contact_name, total_amount, amount_due, status, issue_date, due_date) VALUES
  ('00000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'xero-inv-001', 'INV-001', 'ABC Suppliers', 1500.00, 1500.00, 'AUTHORISED', '2024-01-15', '2024-02-15'),
  ('00000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'xero-inv-002', 'INV-002', 'XYZ Services', 2750.50, 2750.50, 'AUTHORISED', '2024-01-20', '2024-02-20'),
  ('00000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'xero-inv-003', 'INV-003', 'Quick Supplies', 825.25, 825.25, 'AUTHORISED', '2024-01-25', '2024-02-25'),
  ('00000000-0000-0000-0000-000000000004', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'xero-inv-004', 'INV-004', 'Tech Vendor', 3200.00, 3200.00, 'AUTHORISED', '2024-01-10', '2024-02-10');

-- Insert test remittances with different statuses
INSERT INTO public.remittances (id, organisation_id, uploaded_by, status, payment_date, payment_amount, payment_reference, confidence_score) VALUES
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'Data Retrieved', '2024-01-15', 5075.75, 'PAYMENT-001', 95.5),
  ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'All payments matched - Awaiting Approval', '2024-01-20', 1500.00, 'PAYMENT-002', 88.2),
  ('33333333-3333-3333-3333-333333333333', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '55555555-5555-5555-5555-555555555555', 'Exported to Xero - Reconciled', '2024-01-10', 3200.00, 'PAYMENT-003', 92.8);

-- Insert files for remittances
INSERT INTO public.files (remittance_id, organisation_id, storage_path, original_filename, file_size, mime_type, uploaded_by) VALUES
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'remittances/2024/01/payment-001.pdf', 'January Payment Advice.pdf', 245680, 'application/pdf', '33333333-3333-3333-3333-333333333333'),
  ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'remittances/2024/01/payment-002.pdf', 'Supplier Payment.pdf', 189432, 'application/pdf', '33333333-3333-3333-3333-333333333333'),
  ('33333333-3333-3333-3333-333333333333', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'remittances/2024/01/payment-003.pdf', 'Tech Vendor Payment.pdf', 156789, 'application/pdf', '55555555-5555-5555-5555-555555555555');

-- Insert remittance lines (AI extracted + manual overrides)
INSERT INTO public.remittance_lines (remittance_id, invoice_number, ai_paid_amount, ai_invoice_id, manual_paid_amount, override_invoice_id) VALUES
  -- First remittance: Multiple payments, some with overrides
  ('11111111-1111-1111-1111-111111111111', 'INV-001', 1500.00, '00000000-0000-0000-0000-000000000001', NULL, NULL),
  ('11111111-1111-1111-1111-111111111111', 'INV-002', 2750.50, '00000000-0000-0000-0000-000000000002', NULL, NULL),
  ('11111111-1111-1111-1111-111111111111', 'INV-003', 825.25, '00000000-0000-0000-0000-000000000003', NULL, NULL),
  
  -- Second remittance: Single payment with manual override
  ('22222222-2222-2222-2222-222222222222', 'INV-001', 1400.00, '00000000-0000-0000-0000-000000000001', 1500.00, '00000000-0000-0000-0000-000000000001'),
  
  -- Third remittance: Perfect AI match
  ('33333333-3333-3333-3333-333333333333', 'INV-004', 3200.00, '00000000-0000-0000-0000-000000000004', NULL, NULL);

-- Insert audit log entries
INSERT INTO public.audit_log (remittance_id, user_id, action_type, outcome, reason) VALUES
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 'upload', 'success', 'PDF uploaded successfully'),
  ('11111111-1111-1111-1111-111111111111', NULL, 'ai_extraction', 'success', 'AI extracted 3 invoice payments'),
  ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333', 'upload', 'success', 'PDF uploaded successfully'),
  ('22222222-2222-2222-2222-222222222222', NULL, 'ai_extraction', 'success', 'AI extracted 1 invoice payment'),
  ('22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'manual_edit', 'success', 'User corrected payment amount'),
  ('33333333-3333-3333-3333-333333333333', '55555555-5555-5555-5555-555555555555', 'approval', 'success', 'Remittance approved and exported to Xero'),
  ('33333333-3333-3333-3333-333333333333', NULL, 'xero_export', 'success', 'Payment exported to Xero successfully');

-- Insert usage tracking
INSERT INTO public.usage_tracking (organisation_id, month, year, remittances_processed, ai_extractions_count, storage_used_bytes) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1, 2024, 2, 4, 435112),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 1, 2024, 1, 1, 156789);

-- Test computed columns work correctly
-- This should show final_paid_amount = 1500.00 (manual override) and final_invoice_id = inv11111...
SELECT 
  rl.invoice_number,
  rl.ai_paid_amount,
  rl.manual_paid_amount,
  rl.final_paid_amount,
  rl.ai_invoice_id,
  rl.override_invoice_id,
  rl.final_invoice_id
FROM public.remittance_lines rl
WHERE rl.remittance_id = '22222222-2222-2222-2222-222222222222';

-- Test RLS policies by setting a user context
-- This would normally be done by Supabase Auth, but we can simulate it for testing
-- Note: This is just for demonstration - actual RLS testing requires proper auth context