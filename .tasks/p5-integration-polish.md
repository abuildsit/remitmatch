# Phase 5: Integration & Polish

## Overview
This final phase completes the RemitMatch integration by implementing API client improvements, subscription enforcement, comprehensive testing, and deployment preparation.

## Prerequisites
- Phases 1-4 completed
- All core features working locally
- Docker installed for containerization
- GitHub repository set up

## Phase 5.1: API Integration Completion

### Objective
Create a robust API client with proper error handling, authentication, and request/response interceptors.

### Tasks
- [ ] Create API client utility in `apps/web/lib/api/client.ts`:
  ```typescript
  import { toast } from 'sonner';
  
  const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000';
  
  interface ApiRequestOptions extends RequestInit {
    requiresAuth?: boolean;
    showErrorToast?: boolean;
  }
  
  class ApiClient {
    private baseUrl: string;
    
    constructor(baseUrl: string) {
      this.baseUrl = baseUrl;
    }
    
    private async getAuthHeaders(): Promise<HeadersInit> {
      const headers: HeadersInit = {
        'Content-Type': 'application/json',
      };
      
      // Get user ID from session store
      const userId = localStorage.getItem('user_id');
      if (userId) {
        headers['user-id'] = userId;
      }
      
      // Get organisation ID if needed
      const orgId = localStorage.getItem('organisation_id');
      if (orgId) {
        headers['organisation-id'] = orgId;
      }
      
      return headers;
    }
    
    private async handleResponse<T>(response: Response): Promise<T> {
      if (!response.ok) {
        const error = await response.json().catch(() => ({
          message: 'An unexpected error occurred'
        }));
        
        throw new ApiError(
          error.message || response.statusText,
          response.status,
          error
        );
      }
      
      // Handle empty responses
      const text = await response.text();
      return text ? JSON.parse(text) : null;
    }
    
    async request<T>(
      endpoint: string,
      options: ApiRequestOptions = {}
    ): Promise<T> {
      const {
        requiresAuth = true,
        showErrorToast = true,
        headers = {},
        ...fetchOptions
      } = options;
      
      try {
        const authHeaders = requiresAuth ? await this.getAuthHeaders() : {};
        
        const response = await fetch(`${this.baseUrl}${endpoint}`, {
          ...fetchOptions,
          headers: {
            ...authHeaders,
            ...headers,
          },
        });
        
        return await this.handleResponse<T>(response);
      } catch (error) {
        if (showErrorToast && error instanceof ApiError) {
          // Show user-friendly error messages
          if (error.status === 401) {
            toast.error('Session expired. Please log in again.');
          } else if (error.status === 403) {
            toast.error('You do not have permission to perform this action.');
          } else if (error.status === 429) {
            toast.error('Too many requests. Please try again later.');
          } else {
            toast.error(error.message);
          }
        }
        
        throw error;
      }
    }
    
    // Convenience methods
    async get<T>(endpoint: string, options?: ApiRequestOptions): Promise<T> {
      return this.request<T>(endpoint, { ...options, method: 'GET' });
    }
    
    async post<T>(
      endpoint: string,
      data?: any,
      options?: ApiRequestOptions
    ): Promise<T> {
      return this.request<T>(endpoint, {
        ...options,
        method: 'POST',
        body: data ? JSON.stringify(data) : undefined,
      });
    }
    
    async put<T>(
      endpoint: string,
      data?: any,
      options?: ApiRequestOptions
    ): Promise<T> {
      return this.request<T>(endpoint, {
        ...options,
        method: 'PUT',
        body: data ? JSON.stringify(data) : undefined,
      });
    }
    
    async delete<T>(endpoint: string, options?: ApiRequestOptions): Promise<T> {
      return this.request<T>(endpoint, { ...options, method: 'DELETE' });
    }
    
    // File upload method
    async uploadFile(
      endpoint: string,
      formData: FormData,
      options?: Omit<ApiRequestOptions, 'headers'>
    ): Promise<any> {
      const authHeaders = await this.getAuthHeaders();
      delete authHeaders['Content-Type']; // Let browser set multipart boundary
      
      return this.request(endpoint, {
        ...options,
        method: 'POST',
        headers: authHeaders,
        body: formData,
      });
    }
  }
  
  export class ApiError extends Error {
    constructor(
      message: string,
      public status: number,
      public data?: any
    ) {
      super(message);
      this.name = 'ApiError';
    }
  }
  
  // Export singleton instance
  export const apiClient = new ApiClient(API_URL);
  
  // Export typed API methods
  export const api = {
    // Organisations
    organisations: {
      create: (data: any) => apiClient.post('/organisations', data),
      getMembers: (orgId: string) => apiClient.get(`/organisations/${orgId}/members`),
      inviteMember: (orgId: string, data: any) => apiClient.post(`/organisations/${orgId}/members`, data),
    },
    
    // Remittances
    remittances: {
      list: (params: URLSearchParams) => apiClient.get(`/remittances?${params}`),
      get: (id: string) => apiClient.get(`/remittances/${id}`),
      saveOverrides: (id: string, data: any) => apiClient.post(`/remittances/${id}/save-overrides`, data),
      retry: (id: string) => apiClient.post(`/remittances/${id}/retry`),
      approve: (id: string) => apiClient.post(`/remittances/${id}/approve`),
      unapprove: (id: string) => apiClient.post(`/remittances/${id}/unapprove`),
    },
    
    // Files
    files: {
      upload: (formData: FormData) => apiClient.uploadFile('/files/upload', formData),
      getDownloadUrl: (remittanceId: string) => apiClient.get(`/files/${remittanceId}/download`),
    },
    
    // Xero
    xero: {
      connect: (orgId: string) => apiClient.get(`/xero/connect?organisation_id=${orgId}`),
      status: (orgId: string) => apiClient.get(`/xero/status/${orgId}`),
      disconnect: (orgId: string) => apiClient.post(`/xero/disconnect/${orgId}`),
      syncAll: (orgId: string) => apiClient.post('/xero/sync-all', { organisation_id: orgId }),
    },
    
    // Dashboard
    dashboard: {
      summary: (orgId: string) => apiClient.get(`/dashboard/summary/${orgId}`),
    },
    
    // Stripe
    stripe: {
      createCheckout: (data: any) => apiClient.post('/stripe/checkout', data),
    },
  };
  ```
- [ ] Create React Query hooks in `apps/web/lib/hooks/api/use-remittances.ts`:
  ```typescript
  import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
  import { api } from '@/lib/api/client';
  import { Remittance } from '@/lib/types/remittance';
  import { useSession } from '@/lib/hooks/use-session';
  
  export function useRemittances(filters?: Record<string, any>) {
    const { organisation } = useSession();
    
    return useQuery({
      queryKey: ['remittances', organisation.id, filters],
      queryFn: async () => {
        if (!organisation.id) return { remittances: [] };
        
        const params = new URLSearchParams({
          organisation_id: organisation.id,
          ...filters,
        });
        
        return api.remittances.list(params);
      },
      enabled: !!organisation.id,
    });
  }
  
  export function useRemittance(id: string) {
    return useQuery({
      queryKey: ['remittance', id],
      queryFn: () => api.remittances.get(id),
      enabled: !!id,
    });
  }
  
  export function useApproveRemittance() {
    const queryClient = useQueryClient();
    
    return useMutation({
      mutationFn: ({ id, data }: { id: string; data: any }) =>
        api.remittances.saveOverrides(id, data),
      onSuccess: (_, variables) => {
        queryClient.invalidateQueries({ queryKey: ['remittance', variables.id] });
        queryClient.invalidateQueries({ queryKey: ['remittances'] });
      },
    });
  }
  
  export function useRetryExtraction() {
    const queryClient = useQueryClient();
    
    return useMutation({
      mutationFn: (id: string) => api.remittances.retry(id),
      onSuccess: (_, id) => {
        queryClient.invalidateQueries({ queryKey: ['remittance', id] });
      },
    });
  }
  ```
- [ ] Update all API calls to use the new client:
  ```typescript
  // Example: Update FileUpload component
  import { api } from '@/lib/api/client';
  
  // Replace fetch with:
  const data = await api.files.upload(formData);
  ```
- [ ] Add request retry logic to API client:
  ```typescript
  // In ApiClient class, add retry logic:
  private async retryRequest<T>(
    fn: () => Promise<T>,
    retries: number = 3,
    delay: number = 1000
  ): Promise<T> {
    try {
      return await fn();
    } catch (error) {
      if (retries > 0 && error instanceof ApiError && error.status >= 500) {
        await new Promise(resolve => setTimeout(resolve, delay));
        return this.retryRequest(fn, retries - 1, delay * 2);
      }
      throw error;
    }
  }
  ```
- [ ] Implement API request logging in development:
  ```typescript
  // Add to ApiClient constructor:
  if (process.env.NODE_ENV === 'development') {
    this.logRequests = true;
  }
  
  // In request method:
  if (this.logRequests) {
    console.log(`[API] ${fetchOptions.method || 'GET'} ${endpoint}`);
  }
  ```
- [ ] Create error boundary for API errors in `apps/web/components/error-boundary.tsx`:
  ```typescript
  'use client';
  
  import { Component, ReactNode } from 'react';
  import { Button } from '@/components/ui/button';
  import { AlertCircle } from 'lucide-react';
  
  interface Props {
    children: ReactNode;
  }
  
  interface State {
    hasError: boolean;
    error?: Error;
  }
  
  export class ErrorBoundary extends Component<Props, State> {
    constructor(props: Props) {
      super(props);
      this.state = { hasError: false };
    }
    
    static getDerivedStateFromError(error: Error): State {
      return { hasError: true, error };
    }
    
    componentDidCatch(error: Error, errorInfo: any) {
      console.error('Error caught by boundary:', error, errorInfo);
    }
    
    render() {
      if (this.state.hasError) {
        return (
          <div className="flex flex-col items-center justify-center min-h-[400px] p-4">
            <AlertCircle className="h-12 w-12 text-destructive mb-4" />
            <h2 className="text-xl font-semibold mb-2">Something went wrong</h2>
            <p className="text-muted-foreground mb-4 text-center max-w-md">
              {this.state.error?.message || 'An unexpected error occurred'}
            </p>
            <Button
              onClick={() => {
                this.setState({ hasError: false });
                window.location.reload();
              }}
            >
              Try again
            </Button>
          </div>
        );
      }
      
      return this.props.children;
    }
  }
  ```
- [ ] Test all API endpoints with new client
- [ ] Verify error handling works correctly

## Phase 5.2: Subscription & Permissions

### Objective
Implement subscription plan enforcement and role-based access control throughout the application.

### Tasks
- [ ] Create subscription enforcement middleware in `apps/api/app/middleware/subscription.py`:
  ```python
  from fastapi import HTTPException, Header
  from app.database import get_db
  from typing import Dict, Any
  from functools import wraps
  
  # Subscription limits
  SUBSCRIPTION_LIMITS = {
      'free': {'remittances_per_month': 5},
      'business': {'remittances_per_month': 30},
      'pro': {'remittances_per_month': 120},
      'max': {'remittances_per_month': 250}
  }
  
  async def check_subscription_limit(
      organisation_id: str,
      action: str = 'remittance_upload'
  ) -> Dict[str, Any]:
      """Check if organisation has reached subscription limits"""
      db = get_db()
      
      # Get organisation subscription tier
      org_result = db.table('organisations').select(
          'subscription_tier'
      ).eq('id', organisation_id).execute()
      
      if not org_result.data:
          raise HTTPException(status_code=404, detail="Organisation not found")
      
      tier = org_result.data[0].get('subscription_tier', 'free')
      limits = SUBSCRIPTION_LIMITS.get(tier, SUBSCRIPTION_LIMITS['free'])
      
      # Get current month usage
      from datetime import datetime, timezone
      current_month_start = datetime.now(timezone.utc).replace(
          day=1, hour=0, minute=0, second=0, microsecond=0
      )
      
      # Count remittances this month
      count_result = db.table('remittances').select(
          'id', count='exact'
      ).eq('organisation_id', organisation_id).gte(
          'created_at', current_month_start.isoformat()
      ).execute()
      
      current_usage = count_result.count or 0
      limit = limits['remittances_per_month']
      
      return {
          'tier': tier,
          'limit': limit,
          'current_usage': current_usage,
          'remaining': max(0, limit - current_usage),
          'at_limit': current_usage >= limit
      }
  
  def require_subscription(action: str = 'remittance_upload'):
      """Decorator to enforce subscription limits"""
      def decorator(func):
          @wraps(func)
          async def wrapper(*args, **kwargs):
              # Extract organisation_id from kwargs or request
              org_id = kwargs.get('organisation_id')
              if not org_id:
                  # Try to get from request body
                  request = kwargs.get('request')
                  if request and hasattr(request, 'organisation_id'):
                      org_id = request.organisation_id
              
              if org_id:
                  usage = await check_subscription_limit(org_id, action)
                  if usage['at_limit']:
                      raise HTTPException(
                          status_code=402,
                          detail=f"Subscription limit reached. Current plan allows {usage['limit']} remittances per month."
                      )
              
              return await func(*args, **kwargs)
          return wrapper
      return decorator
  ```
- [ ] Create permission checking utilities in `apps/api/app/middleware/permissions.py`:
  ```python
  from fastapi import HTTPException, Header
  from app.database import get_db
  from app.models.database import OrganisationRole
  from typing import List, Optional
  from functools import wraps
  
  async def get_user_role(
      user_id: str,
      organisation_id: str
  ) -> Optional[OrganisationRole]:
      """Get user's role in an organisation"""
      db = get_db()
      
      result = db.table('organisation_members').select('role').eq(
          'user_id', user_id
      ).eq('organisation_id', organisation_id).execute()
      
      if result.data:
          return OrganisationRole(result.data[0]['role'])
      return None
  
  def require_role(allowed_roles: List[OrganisationRole]):
      """Decorator to enforce role-based access"""
      def decorator(func):
          @wraps(func)
          async def wrapper(*args, **kwargs):
              user_id = kwargs.get('user_id')
              org_id = kwargs.get('organisation_id')
              
              if not user_id or not org_id:
                  raise HTTPException(
                      status_code=400,
                      detail="User ID and Organisation ID required"
                  )
              
              role = await get_user_role(user_id, org_id)
              if not role or role not in allowed_roles:
                  raise HTTPException(
                      status_code=403,
                      detail="Insufficient permissions"
                  )
              
              # Add role to kwargs for use in function
              kwargs['user_role'] = role
              return await func(*args, **kwargs)
          return wrapper
      return decorator
  
  # Convenience decorators
  def admin_only(func):
      return require_role([OrganisationRole.OWNER, OrganisationRole.ADMIN])(func)
  
  def can_approve(func):
      return require_role([
          OrganisationRole.OWNER,
          OrganisationRole.ADMIN,
          OrganisationRole.USER
      ])(func)
  ```
- [ ] Update file upload endpoint with subscription check:
  ```python
  from app.middleware.subscription import require_subscription
  
  @router.post("/upload", response_model=FileUploadResponse)
  @require_subscription('remittance_upload')
  async def upload_remittance_file(
      file: UploadFile = File(...),
      organisation_id: str = Form(...),
      user_id: str = Header(...)
  ):
      # Existing implementation
  ```
- [ ] Add subscription status endpoint in `apps/api/app/routers/subscriptions.py`:
  ```python
  from fastapi import APIRouter, HTTPException, Header
  from app.middleware.subscription import check_subscription_limit
  from app.utils.database_helpers import check_organisation_access
  
  router = APIRouter()
  
  @router.get("/usage/{organisation_id}")
  async def get_subscription_usage(
      organisation_id: str,
      user_id: str = Header(...)
  ):
      """Get current subscription usage"""
      if not await check_organisation_access(user_id, organisation_id):
          raise HTTPException(status_code=403, detail="Access denied")
      
      usage = await check_subscription_limit(organisation_id)
      return usage
  
  @router.get("/plans")
  async def get_subscription_plans():
      """Get available subscription plans"""
      return {
          'plans': [
              {
                  'id': 'free',
                  'name': 'Free',
                  'price': 0,
                  'currency': 'AUD',
                  'remittances_per_month': 5,
                  'features': ['Basic features', '5 remittances/month']
              },
              {
                  'id': 'business',
                  'name': 'Business',
                  'price': 15,
                  'currency': 'AUD',
                  'remittances_per_month': 30,
                  'features': ['All features', '30 remittances/month', 'Priority support']
              },
              {
                  'id': 'pro',
                  'name': 'Pro',
                  'price': 30,
                  'currency': 'AUD',
                  'remittances_per_month': 120,
                  'features': ['All features', '120 remittances/month', 'Priority support']
              },
              {
                  'id': 'max',
                  'name': 'Max',
                  'price': 50,
                  'currency': 'AUD',
                  'remittances_per_month': 250,
                  'features': ['All features', '250 remittances/month', 'Dedicated support']
              }
          ]
      }
  ```
- [ ] Create subscription status component in `apps/web/components/subscription-status.tsx`:
  ```typescript
  'use client';
  
  import { useQuery } from '@tanstack/react-query';
  import { Progress } from '@/components/ui/progress';
  import { Button } from '@/components/ui/button';
  import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
  import { api } from '@/lib/api/client';
  import { useSession } from '@/lib/hooks/use-session';
  import { useRouter } from 'next/navigation';
  
  export function SubscriptionStatus() {
    const router = useRouter();
    const { organisation } = useSession();
    
    const { data: usage, isLoading } = useQuery({
      queryKey: ['subscription-usage', organisation.id],
      queryFn: () => api.subscriptions.usage(organisation.id!),
      enabled: !!organisation.id,
    });
    
    if (isLoading || !usage) return null;
    
    const percentUsed = (usage.current_usage / usage.limit) * 100;
    const isNearLimit = percentUsed >= 80;
    const isAtLimit = usage.at_limit;
    
    return (
      <Card className={isAtLimit ? 'border-destructive' : ''}>
        <CardHeader>
          <CardTitle className="text-lg">Monthly Usage</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span>Remittances</span>
              <span className={isNearLimit ? 'text-destructive' : ''}>
                {usage.current_usage} / {usage.limit}
              </span>
            </div>
            <Progress 
              value={percentUsed} 
              className={isNearLimit ? 'bg-destructive/20' : ''}
            />
            <p className="text-xs text-muted-foreground">
              {usage.remaining} remaining this month
            </p>
            {isNearLimit && (
              <Button
                size="sm"
                variant={isAtLimit ? 'default' : 'outline'}
                className="w-full mt-2"
                onClick={() => router.push('/dashboard/settings?tab=subscription')}
              >
                {isAtLimit ? 'Upgrade Now' : 'View Plans'}
              </Button>
            )}
          </div>
        </CardContent>
      </Card>
    );
  }
  ```
- [ ] Add role-based UI conditionals:
  ```typescript
  // In remittance detail page
  const { canApproveRemittances, canManageUsers } = useSession();
  
  // Show approve button only if user has permission
  {canApproveRemittances && (
    <Button onClick={handleApprove}>Approve</Button>
  )}
  ```
- [ ] Test subscription limits work correctly
- [ ] Verify role-based permissions are enforced

## Phase 5.3: Testing & Refinement

### Objective
Implement comprehensive testing, optimize performance, and refine the user experience.

### Tasks
- [ ] Create E2E test scenarios in `apps/web/e2e/remittance-flow.spec.ts`:
  ```typescript
  import { test, expect } from '@playwright/test';
  
  test.describe('Remittance Flow', () => {
    test.beforeEach(async ({ page }) => {
      // Login and select organisation
      await page.goto('/sign-in');
      await page.fill('[name="email"]', 'test@example.com');
      await page.fill('[name="password"]', 'password');
      await page.click('button[type="submit"]');
      await page.waitForURL('/dashboard');
    });
    
    test('should upload and process remittance', async ({ page }) => {
      // Navigate to remittances
      await page.goto('/dashboard/remittances');
      
      // Click upload button
      await page.click('button:has-text("Upload Remittance")');
      
      // Upload file
      const fileInput = await page.locator('input[type="file"]');
      await fileInput.setInputFiles('test-files/sample-remittance.pdf');
      
      // Click upload
      await page.click('button:has-text("Upload")');
      
      // Wait for processing
      await expect(page.locator('text=File uploaded successfully')).toBeVisible();
      
      // Verify remittance appears in list
      await expect(page.locator('table tbody tr')).toHaveCount(1);
    });
    
    test('should handle manual override and approval', async ({ page }) => {
      // Navigate to existing remittance
      await page.goto('/dashboard/remittances/test-remittance-id');
      
      // Edit amount
      await page.fill('input[type="number"]', '500.00');
      
      // Select invoice from dropdown
      await page.click('[role="combobox"]');
      await page.click('text=INV-001');
      
      // Save and approve
      await page.click('button:has-text("Save + Approve")');
      
      // Verify status update
      await expect(page.locator('text=Exported to Xero')).toBeVisible();
    });
    
    test('should enforce subscription limits', async ({ page }) => {
      // Set user to free tier with 5 remittances already
      // Upload 6th remittance
      await page.goto('/dashboard/remittances');
      await page.click('button:has-text("Upload Remittance")');
      
      const fileInput = await page.locator('input[type="file"]');
      await fileInput.setInputFiles('test-files/sample-remittance.pdf');
      await page.click('button:has-text("Upload")');
      
      // Should show limit error
      await expect(page.locator('text=Subscription limit reached')).toBeVisible();
    });
  });
  ```
- [ ] Add performance monitoring in `apps/web/lib/monitoring/performance.ts`:
  ```typescript
  export function measureApiCall(name: string) {
    const start = performance.now();
    
    return {
      end: () => {
        const duration = performance.now() - start;
        if (process.env.NODE_ENV === 'development') {
          console.log(`[Performance] ${name}: ${duration.toFixed(2)}ms`);
        }
        
        // Send to analytics in production
        if (typeof window !== 'undefined' && window.analytics) {
          window.analytics.track('api_performance', {
            name,
            duration,
          });
        }
      }
    };
  }
  ```
- [ ] Optimize bundle size:
  ```bash
  cd apps/web
  npm run build
  npm run analyze  # Add bundle analyzer
  ```
- [ ] Create loading skeletons in `apps/web/components/ui/skeleton.tsx`:
  ```typescript
  import { cn } from '@/lib/utils';
  
  function Skeleton({
    className,
    ...props
  }: React.HTMLAttributes<HTMLDivElement>) {
    return (
      <div
        className={cn('animate-pulse rounded-md bg-muted', className)}
        {...props}
      />
    );
  }
  
  export { Skeleton };
  
  // Remittance list skeleton
  export function RemittanceListSkeleton() {
    return (
      <div className="space-y-3">
        {[...Array(5)].map((_, i) => (
          <div key={i} className="flex items-center space-x-4">
            <Skeleton className="h-12 w-12 rounded-full" />
            <div className="space-y-2">
              <Skeleton className="h-4 w-[250px]" />
              <Skeleton className="h-4 w-[200px]" />
            </div>
          </div>
        ))}
      </div>
    );
  }
  ```
- [ ] Add analytics tracking in `apps/web/lib/analytics/index.ts`:
  ```typescript
  export const analytics = {
    track: (event: string, properties?: Record<string, any>) => {
      if (typeof window !== 'undefined' && window.gtag) {
        window.gtag('event', event, properties);
      }
      
      // Also send to backend for internal analytics
      if (process.env.NODE_ENV === 'production') {
        fetch('/api/analytics', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ event, properties }),
        }).catch(() => {
          // Fail silently
        });
      }
    },
    
    page: (name: string, properties?: Record<string, any>) => {
      analytics.track('page_view', { page_name: name, ...properties });
    },
  };
  ```
- [ ] Implement keyboard shortcuts in `apps/web/hooks/use-keyboard-shortcuts.ts`:
  ```typescript
  import { useEffect } from 'react';
  import { useRouter } from 'next/navigation';
  import { useSessionStore } from '@/lib/stores/session';
  
  export function useKeyboardShortcuts() {
    const router = useRouter();
    const { organisation_id } = useSessionStore();
    
    useEffect(() => {
      const handleKeyPress = (e: KeyboardEvent) => {
        // Cmd/Ctrl + K for search
        if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
          e.preventDefault();
          // Open search modal
        }
        
        // Cmd/Ctrl + U for upload
        if ((e.metaKey || e.ctrlKey) && e.key === 'u') {
          e.preventDefault();
          router.push('/dashboard/remittances?action=upload');
        }
        
        // ESC to go back
        if (e.key === 'Escape') {
          router.back();
        }
      };
      
      window.addEventListener('keydown', handleKeyPress);
      return () => window.removeEventListener('keydown', handleKeyPress);
    }, [router, organisation_id]);
  }
  ```
- [ ] Add accessibility improvements:
  ```typescript
  // Add ARIA labels
  <Button aria-label="Upload new remittance">
    <Upload className="mr-2 h-4 w-4" />
    Upload Remittance
  </Button>
  
  // Add focus management
  useEffect(() => {
    const mainHeading = document.querySelector('h1');
    mainHeading?.focus();
  }, []);
  ```
- [ ] Create user onboarding flow in `apps/web/components/onboarding/index.tsx`:
  ```typescript
  import { useState, useEffect } from 'react';
  import { Card } from '@/components/ui/card';
  import { Button } from '@/components/ui/button';
  import { useSession } from '@/lib/hooks/use-session';
  
  const ONBOARDING_STEPS = [
    {
      id: 'connect-xero',
      title: 'Connect to Xero',
      description: 'Link your accounting software to sync invoices',
      action: '/dashboard/settings',
    },
    {
      id: 'upload-first',
      title: 'Upload Your First Remittance',
      description: 'Try uploading a PDF remittance advice',
      action: '/dashboard/remittances?action=upload',
    },
    {
      id: 'review-matches',
      title: 'Review and Approve',
      description: 'Check the AI matches and approve payments',
      action: '/dashboard/remittances',
    },
  ];
  
  export function OnboardingChecklist() {
    const { organisation } = useSession();
    const [completed, setCompleted] = useState<string[]>([]);
    
    useEffect(() => {
      // Load completed steps from localStorage
      const saved = localStorage.getItem(`onboarding_${organisation.id}`);
      if (saved) {
        setCompleted(JSON.parse(saved));
      }
    }, [organisation.id]);
    
    const markComplete = (stepId: string) => {
      const updated = [...completed, stepId];
      setCompleted(updated);
      localStorage.setItem(
        `onboarding_${organisation.id}`,
        JSON.stringify(updated)
      );
    };
    
    if (completed.length === ONBOARDING_STEPS.length) {
      return null;
    }
    
    return (
      <Card className="p-4">
        <h3 className="font-semibold mb-3">Getting Started</h3>
        <div className="space-y-2">
          {ONBOARDING_STEPS.map((step) => {
            const isComplete = completed.includes(step.id);
            return (
              <div
                key={step.id}
                className={`flex items-center justify-between p-2 rounded ${
                  isComplete ? 'opacity-50' : ''
                }`}
              >
                <div>
                  <p className="font-medium text-sm">{step.title}</p>
                  <p className="text-xs text-muted-foreground">
                    {step.description}
                  </p>
                </div>
                {!isComplete && (
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => {
                      window.location.href = step.action;
                      markComplete(step.id);
                    }}
                  >
                    Start
                  </Button>
                )}
              </div>
            );
          })}
        </div>
      </Card>
    );
  }
  ```
- [ ] Run full test suite
- [ ] Test on different browsers
- [ ] Verify mobile responsiveness

## Phase 5.4: Deployment Preparation

### Objective
Prepare the application for production deployment with proper configuration, monitoring, and CI/CD setup.

### Tasks
- [ ] Create Dockerfile for FastAPI in `apps/api/Dockerfile`:
  ```dockerfile
  FROM python:3.11-slim
  
  WORKDIR /app
  
  # Install system dependencies
  RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*
  
  # Copy requirements first for better caching
  COPY requirements.txt .
  RUN pip install --no-cache-dir -r requirements.txt
  
  # Copy application code
  COPY . .
  
  # Create non-root user
  RUN useradd -m -u 1000 apiuser && chown -R apiuser:apiuser /app
  USER apiuser
  
  # Expose port
  EXPOSE 8000
  
  # Run with gunicorn in production
  CMD ["gunicorn", "main:app", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8000"]
  ```
- [ ] Create docker-compose for local development in `docker-compose.yml`:
  ```yaml
  version: '3.8'
  
  services:
    api:
      build:
        context: ./apps/api
        dockerfile: Dockerfile
      ports:
        - "8000:8000"
      environment:
        - API_ENV=development
        - DATABASE_URL=${DATABASE_URL}
      volumes:
        - ./apps/api:/app
      command: python run.py
    
    web:
      build:
        context: ./apps/web
        dockerfile: Dockerfile
      ports:
        - "3000:3000"
      environment:
        - NEXT_PUBLIC_API_URL=http://localhost:8000
      volumes:
        - ./apps/web:/app
        - /app/node_modules
      command: npm run dev
  ```
- [ ] Create production environment configuration:
  ```bash
  # apps/web/.env.production
  NEXT_PUBLIC_API_URL=https://api.remitmatch.com
  NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
  NEXT_PUBLIC_SUPABASE_ANON_KEY=your-production-anon-key
  
  # apps/api/.env.production
  API_ENV=production
  SUPABASE_URL=https://your-project.supabase.co
  SUPABASE_SERVICE_KEY=your-production-service-key
  SENTRY_DSN=your-sentry-dsn
  ```
- [ ] Set up GitHub Actions for CI/CD in `.github/workflows/deploy.yml`:
  ```yaml
  name: Deploy
  
  on:
    push:
      branches: [main]
    pull_request:
      branches: [main]
  
  jobs:
    test:
      runs-on: ubuntu-latest
      
      steps:
        - uses: actions/checkout@v3
        
        - name: Setup Node.js
          uses: actions/setup-node@v3
          with:
            node-version: '18'
            
        - name: Install dependencies
          run: |
            cd apps/web
            npm ci
            
        - name: Run tests
          run: |
            cd apps/web
            npm test
            
        - name: Build
          run: |
            cd apps/web
            npm run build
  
    deploy-api:
      needs: test
      runs-on: ubuntu-latest
      if: github.ref == 'refs/heads/main'
      
      steps:
        - uses: actions/checkout@v3
        
        - name: Deploy to Render
          env:
            RENDER_API_KEY: ${{ secrets.RENDER_API_KEY }}
          run: |
            curl -X POST \
              -H "Authorization: Bearer $RENDER_API_KEY" \
              https://api.render.com/v1/services/${{ secrets.RENDER_SERVICE_ID }}/deploys
  
    deploy-web:
      needs: test
      runs-on: ubuntu-latest
      if: github.ref == 'refs/heads/main'
      
      steps:
        - uses: actions/checkout@v3
        
        - name: Deploy to Vercel
          uses: amondnet/vercel-action@v20
          with:
            vercel-token: ${{ secrets.VERCEL_TOKEN }}
            vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
            vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
            vercel-args: '--prod'
  ```
- [ ] Set up monitoring with Sentry in `apps/web/lib/monitoring/sentry.ts`:
  ```typescript
  import * as Sentry from '@sentry/nextjs';
  
  export function initSentry() {
    if (process.env.NODE_ENV === 'production') {
      Sentry.init({
        dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
        environment: process.env.NODE_ENV,
        tracesSampleRate: 0.1,
        beforeSend(event) {
          // Don't send sensitive data
          if (event.request?.cookies) {
            delete event.request.cookies;
          }
          return event;
        },
      });
    }
  }
  ```
- [ ] Create health check endpoints:
  ```python
  # In apps/api/main.py
  @app.get("/health/ready")
  async def readiness_check():
      """Check if service is ready to handle requests"""
      checks = {
          'database': False,
          'storage': False,
          'external_apis': False
      }
      
      # Check database
      try:
          db = get_db()
          db.table('organisations').select('count').limit(1).execute()
          checks['database'] = True
      except:
          pass
      
      # Check storage
      try:
          # Test storage access
          checks['storage'] = True
      except:
          pass
      
      all_healthy = all(checks.values())
      status_code = 200 if all_healthy else 503
      
      return JSONResponse(
          status_code=status_code,
          content={
              'status': 'ready' if all_healthy else 'not ready',
              'checks': checks
          }
      )
  ```
- [ ] Create deployment documentation in `docs/deployment.md`:
  ```markdown
  # Deployment Guide
  
  ## Prerequisites
  - Vercel account
  - Render.com account
  - Supabase project
  - Domain configured
  
  ## Environment Variables
  
  ### Frontend (Vercel)
  - `NEXT_PUBLIC_API_URL`
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  - `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`
  - `CLERK_SECRET_KEY`
  
  ### Backend (Render)
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_KEY`
  - `OPENAI_API_KEY`
  - `STRIPE_SECRET_KEY`
  - `XERO_CLIENT_ID`
  - `XERO_CLIENT_SECRET`
  
  ## Deployment Steps
  
  1. Set up Supabase project
  2. Configure environment variables
  3. Deploy backend to Render
  4. Deploy frontend to Vercel
  5. Configure custom domains
  6. Set up monitoring
  ```
- [ ] Create pre-deployment checklist:
  ```markdown
  ## Pre-Deployment Checklist
  
  - [ ] All tests passing
  - [ ] Environment variables configured
  - [ ] Database migrations applied
  - [ ] Storage buckets created
  - [ ] API rate limiting configured
  - [ ] Error tracking set up
  - [ ] SSL certificates configured
  - [ ] Backup strategy in place
  - [ ] Monitoring alerts configured
  - [ ] Documentation updated
  ```
- [ ] Test deployment process
- [ ] Verify production builds work

## Verification Checklist
- [ ] API client handles all error cases gracefully
- [ ] Subscription limits are enforced correctly
- [ ] Role-based permissions work as expected
- [ ] All E2E tests pass
- [ ] Performance metrics are acceptable
- [ ] Accessibility standards are met
- [ ] Docker containers build and run
- [ ] CI/CD pipeline executes successfully
- [ ] Health checks return correct status
- [ ] Monitoring is capturing events

## Final Steps
- [ ] Security audit (check for exposed secrets, SQL injection, XSS)
- [ ] Performance audit (Lighthouse, bundle analysis)
- [ ] User acceptance testing
- [ ] Create user documentation
- [ ] Set up customer support workflows
- [ ] Plan post-launch monitoring

## Congratulations!
Once Phase 5 is complete, RemitMatch is ready for production deployment. The application now has:
- Robust error handling and monitoring
- Subscription management
- Role-based access control
- Comprehensive testing
- Production-ready infrastructure
- CI/CD automation