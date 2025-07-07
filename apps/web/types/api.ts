// ============================================================================
// API Response Types
// ============================================================================

export interface ApiResponse<T = any> {
  data: T;
  message?: string;
  success: boolean;
}

export interface ApiError {
  message: string;
  code?: string;
  details?: any;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    totalPages: number;
    hasNext: boolean;
    hasPrev: boolean;
  };
}

// ============================================================================
// Health Check Types
// ============================================================================

export interface HealthCheckResponse {
  status: 'healthy' | 'unhealthy';
  timestamp: string;
  version?: string;
  uptime?: number;
  database?: {
    status: 'connected' | 'disconnected';
    responseTime?: number;
  };
  services?: {
    name: string;
    status: 'healthy' | 'unhealthy';
    responseTime?: number;
  }[];
}

// ============================================================================
// User Types
// ============================================================================

export interface User {
  id: string;
  email: string;
  full_name?: string;
  created_at: string;
  updated_at: string;
}

// ============================================================================
// Organization Types
// ============================================================================

export interface Organisation {
  id: string;
  name: string;
  xero_tenant_id?: string;
  created_by: string;
  created_at: string;
  updated_at: string;
}

export interface OrganisationMember {
  id: string;
  user_id: string;
  organisation_id: string;
  role: 'owner' | 'admin' | 'user' | 'auditor';
  created_at: string;
  updated_at: string;
  user?: User;
  organisation?: Organisation;
}

// ============================================================================
// Subscription Types
// ============================================================================

export interface OrgSubscription {
  id: string;
  organisation_id: string;
  stripe_customer_id: string;
  stripe_subscription_id: string;
  status: string;
  tier: 'free' | 'business' | 'pro' | 'max';
  current_period_start?: string;
  current_period_end?: string;
  created_at: string;
  updated_at: string;
}

// ============================================================================
// Remittance Types
// ============================================================================

export type RemittanceStatus = 
  | 'Uploaded'
  | 'Data Retrieved'
  | 'All payments matched - Awaiting Approval'
  | 'Error - Payments Unmatched'
  | 'Exported to Xero - Unreconciled'
  | 'Exported to Xero - Reconciled'
  | 'Export Failed'
  | 'Soft Deleted';

export interface Remittance {
  id: string;
  organisation_id: string;
  uploaded_by: string;
  status: RemittanceStatus;
  payment_date?: string;
  payment_amount?: number;
  payment_reference?: string;
  confidence_score?: number;
  ai_extracted_data?: any;
  approved_at?: string;
  approved_by?: string;
  exported_at?: string;
  xero_payment_id?: string;
  deleted_at?: string;
  deleted_by?: string;
  created_at: string;
  updated_at: string;
  
  // Relations
  remittance_lines?: RemittanceLine[];
  files?: File[];
  uploaded_by_user?: User;
}

export interface RemittanceLine {
  id: string;
  remittance_id: string;
  invoice_number: string;
  ai_paid_amount: number;
  ai_invoice_id?: string;
  manual_paid_amount?: number;
  override_invoice_id?: string;
  final_paid_amount: number;
  final_invoice_id?: string;
  created_at: string;
  updated_at: string;
  
  // Relations
  ai_invoice?: XeroInvoice;
  override_invoice?: XeroInvoice;
}

// ============================================================================
// Xero Integration Types
// ============================================================================

export interface XeroIntegration {
  id: string;
  organisation_id: string;
  xero_tenant_id: string;
  access_token: string;
  refresh_token: string;
  expires_at: string;
  token_set?: any;
  connected_at: string;
  last_sync_at?: string;
  created_at: string;
  updated_at: string;
}

export interface BankAccount {
  id: string;
  organisation_id: string;
  xero_account_id: string;
  account_name: string;
  account_code?: string;
  account_type?: string;
  is_default: boolean;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface XeroInvoice {
  id: string;
  organisation_id: string;
  xero_invoice_id: string;
  invoice_number?: string;
  contact_name?: string;
  total_amount?: number;
  amount_due?: number;
  currency: string;
  status?: string;
  issue_date?: string;
  due_date?: string;
  xero_updated_date?: string;
  last_synced_at: string;
  created_at: string;
  updated_at: string;
}

// ============================================================================
// File Types
// ============================================================================

export interface File {
  id: string;
  organisation_id: string;
  remittance_id: string;
  storage_path: string;
  original_filename: string;
  file_size?: number;
  mime_type?: string;
  uploaded_by: string;
  uploaded_at: string;
}

// ============================================================================
// Audit Log Types
// ============================================================================

export type AuditAction = 
  | 'upload'
  | 'ai_extraction'
  | 'manual_edit'
  | 'approval'
  | 'unapproval'
  | 'xero_export'
  | 'xero_sync'
  | 'soft_delete'
  | 'restore'
  | 'retry';

export interface AuditLog {
  id: string;
  remittance_id: string;
  user_id?: string;
  action_type: AuditAction;
  field_name?: string;
  old_value?: string;
  new_value?: string;
  outcome?: 'success' | 'error' | 'warning';
  error_message?: string;
  reason?: string;
  ip_address?: string;
  user_agent?: string;
  created_at: string;
  
  // Relations
  user?: User;
}

// ============================================================================
// Usage Tracking Types
// ============================================================================

export interface UsageTracking {
  id: string;
  organisation_id: string;
  month: number;
  year: number;
  remittances_processed: number;
  ai_extractions_count: number;
  storage_used_bytes: number;
  created_at: string;
  updated_at: string;
}