# Phase 3: State Management & Authentication

## Overview
This phase implements Zustand for global state management, sets up organisation context handling, and integrates Xero OAuth authentication alongside the existing Clerk authentication.

## Prerequisites
- Phase 1 & 2 completed (FastAPI running, database migrated)
- Local Supabase running
- Xero developer account and OAuth app credentials

## Phase 3.1: Zustand Store Setup

### Objective
Implement a global state management solution using Zustand to handle session data, organisation context, and multi-tenant state.

### Tasks
- [ ] Install Zustand in the web app:
  ```bash
  cd apps/web
  npm install zustand
  npm install --save-dev @types/node
  ```
- [ ] Create store directory structure:
  ```bash
  mkdir -p lib/stores
  ```
- [ ] Create TypeScript types for session state in `apps/web/lib/stores/types.ts`:
  ```typescript
  export type OrganisationRole = 'owner' | 'admin' | 'user' | 'auditor';
  export type SubscriptionTier = 'free' | 'business' | 'pro' | 'max';
  
  export interface Organisation {
    id: string;
    name: string;
    subscription_tier: SubscriptionTier;
  }
  
  export interface SessionState {
    // User info
    user_id: string | null;
    user_email: string | null;
    user_display_name: string | null;
    
    // Organisation context
    organisation_id: string | null;
    organisation_name: string | null;
    role: OrganisationRole | null;
    subscription_tier: SubscriptionTier | null;
    
    // Multi-org support
    org_membership_ids: string[];
    organisations: Organisation[];
    
    // RemitMatch specific
    active_remittance_id: string | null;
    
    // Actions
    setUser: (user: { id: string; email: string; display_name: string }) => void;
    setActiveOrganisation: (orgId: string) => Promise<void>;
    setActiveRemittance: (remittanceId: string | null) => void;
    loadUserOrganisations: () => Promise<void>;
    clearSession: () => void;
    hydrate: () => Promise<void>;
  }
  ```
- [ ] Create the Zustand store in `apps/web/lib/stores/session.ts`:
  ```typescript
  import { create } from 'zustand';
  import { persist, createJSONStorage } from 'zustand/middleware';
  import { SessionState } from './types';
  
  const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000';
  
  export const useSessionStore = create<SessionState>()(
    persist(
      (set, get) => ({
        // Initial state
        user_id: null,
        user_email: null,
        user_display_name: null,
        organisation_id: null,
        organisation_name: null,
        role: null,
        subscription_tier: null,
        org_membership_ids: [],
        organisations: [],
        active_remittance_id: null,
        
        // Actions
        setUser: (user) => set({
          user_id: user.id,
          user_email: user.email,
          user_display_name: user.display_name,
        }),
        
        setActiveOrganisation: async (orgId) => {
          const { organisations } = get();
          const org = organisations.find(o => o.id === orgId);
          
          if (!org) {
            console.error('Organisation not found:', orgId);
            return;
          }
          
          // Get user's role in this organisation
          try {
            const response = await fetch(`${API_URL}/organisations/${orgId}/member`, {
              headers: {
                'user-id': get().user_id || '',
              },
            });
            
            if (response.ok) {
              const data = await response.json();
              set({
                organisation_id: orgId,
                organisation_name: org.name,
                subscription_tier: org.subscription_tier,
                role: data.role,
              });
              
              // Store in localStorage for cross-tab sync
              localStorage.setItem('active_organisation', orgId);
            }
          } catch (error) {
            console.error('Error setting active organisation:', error);
          }
        },
        
        setActiveRemittance: (remittanceId) => set({ active_remittance_id: remittanceId }),
        
        loadUserOrganisations: async () => {
          const { user_id } = get();
          if (!user_id) return;
          
          try {
            const response = await fetch(`${API_URL}/users/${user_id}/organisations`);
            if (response.ok) {
              const data = await response.json();
              set({
                organisations: data.organisations,
                org_membership_ids: data.organisations.map((o: Organisation) => o.id),
              });
              
              // If no active org set, use the first one
              if (!get().organisation_id && data.organisations.length > 0) {
                await get().setActiveOrganisation(data.organisations[0].id);
              }
            }
          } catch (error) {
            console.error('Error loading organisations:', error);
          }
        },
        
        clearSession: () => set({
          user_id: null,
          user_email: null,
          user_display_name: null,
          organisation_id: null,
          organisation_name: null,
          role: null,
          subscription_tier: null,
          org_membership_ids: [],
          organisations: [],
          active_remittance_id: null,
        }),
        
        hydrate: async () => {
          // This will be called on app load to sync with backend
          const { user_id } = get();
          if (user_id) {
            await get().loadUserOrganisations();
          }
        },
      }),
      {
        name: 'remitmatch-session',
        storage: createJSONStorage(() => localStorage),
        partialize: (state) => ({
          user_id: state.user_id,
          organisation_id: state.organisation_id,
        }),
      }
    )
  );
  ```
- [ ] Create a session provider component in `apps/web/lib/stores/session-provider.tsx`:
  ```typescript
  'use client';
  
  import { useEffect } from 'react';
  import { useUser } from '@clerk/nextjs';
  import { useSessionStore } from './session';
  
  export function SessionProvider({ children }: { children: React.ReactNode }) {
    const { user, isLoaded } = useUser();
    const { setUser, hydrate, clearSession } = useSessionStore();
    
    useEffect(() => {
      if (isLoaded) {
        if (user) {
          setUser({
            id: user.id,
            email: user.emailAddresses[0]?.emailAddress || '',
            display_name: user.fullName || user.firstName || 'User',
          });
          hydrate();
        } else {
          clearSession();
        }
      }
    }, [user, isLoaded, setUser, hydrate, clearSession]);
    
    // Listen for cross-tab organisation changes
    useEffect(() => {
      const handleStorageChange = (e: StorageEvent) => {
        if (e.key === 'active_organisation' && e.newValue) {
          // Reload the page to ensure consistency
          window.location.reload();
        }
      };
      
      window.addEventListener('storage', handleStorageChange);
      return () => window.removeEventListener('storage', handleStorageChange);
    }, []);
    
    return <>{children}</>;
  }
  ```
- [ ] Update `apps/web/app/provider.tsx` to include SessionProvider:
  ```typescript
  "use client";
  import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
  import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
  import { ReactNode, useState } from "react";
  import { SessionProvider } from "@/lib/stores/session-provider";
  
  export default function Provider({ children }: { children: ReactNode }) {
    const [queryClient] = useState(() => new QueryClient());
  
    return (
      <QueryClientProvider client={queryClient}>
        <SessionProvider>
          <ReactQueryDevtools initialIsOpen={false} />
          {children}
        </SessionProvider>
      </QueryClientProvider>
    );
  }
  ```
- [ ] Create a custom hook for easy access in `apps/web/lib/hooks/use-session.ts`:
  ```typescript
  import { useSessionStore } from '@/lib/stores/session';
  
  export function useSession() {
    const session = useSessionStore();
    
    return {
      user: {
        id: session.user_id,
        email: session.user_email,
        displayName: session.user_display_name,
      },
      organisation: {
        id: session.organisation_id,
        name: session.organisation_name,
        role: session.role,
        subscriptionTier: session.subscription_tier,
      },
      isAuthenticated: !!session.user_id,
      hasOrganisation: !!session.organisation_id,
      canManageUsers: session.role === 'owner' || session.role === 'admin',
      canApproveRemittances: session.role !== 'auditor',
      setActiveOrganisation: session.setActiveOrganisation,
      setActiveRemittance: session.setActiveRemittance,
    };
  }
  ```
- [ ] Test Zustand store with React DevTools
- [ ] Verify persistence works across page refreshes

## Phase 3.2: Organisation Management

### Objective
Implement organisation creation, member management, and switching functionality.

### Tasks
- [ ] Create organisation API endpoints in `apps/api/app/routers/organisations.py`:
  ```python
  from fastapi import APIRouter, HTTPException, Header
  from typing import Optional, List
  from app.database import get_db
  from app.models.database import Organisation, OrganisationMember, OrganisationRole
  from app.utils.database_helpers import check_organisation_access, create_audit_log
  from pydantic import BaseModel
  import uuid
  
  router = APIRouter()
  
  class CreateOrganisationRequest(BaseModel):
      name: str
      xero_tenant_id: Optional[str] = None
  
  class InviteMemberRequest(BaseModel):
      email: str
      role: OrganisationRole = OrganisationRole.USER
  
  @router.post("/")
  async def create_organisation(
      request: CreateOrganisationRequest,
      user_id: str = Header(...)
  ):
      """Create a new organisation"""
      try:
          db = get_db()
          
          # Check if org with xero_tenant_id already exists
          if request.xero_tenant_id:
              existing = db.table('organisations').select('*').eq(
                  'xero_tenant_id', request.xero_tenant_id
              ).execute()
              
              if existing.data:
                  raise HTTPException(
                      status_code=400,
                      detail="Organisation with this Xero account already exists"
                  )
          
          # Create organisation
          org_data = {
              'name': request.name,
              'xero_tenant_id': request.xero_tenant_id,
          }
          
          org_result = db.table('organisations').insert(org_data).execute()
          organisation = org_result.data[0]
          
          # Add creator as owner
          member_data = {
              'organisation_id': organisation['id'],
              'user_id': user_id,
              'role': OrganisationRole.OWNER,
          }
          
          db.table('organisation_members').insert(member_data).execute()
          
          # Create audit log
          await create_audit_log(
              organisation_id=organisation['id'],
              user_id=user_id,
              action='organisation_created',
              outcome='success'
          )
          
          return {"organisation": organisation}
          
      except HTTPException:
          raise
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  
  @router.get("/{org_id}/members")
  async def get_organisation_members(
      org_id: str,
      user_id: str = Header(...)
  ):
      """Get organisation members"""
      # Check access
      if not await check_organisation_access(user_id, org_id):
          raise HTTPException(status_code=403, detail="Access denied")
      
      try:
          db = get_db()
          result = db.table('organisation_members').select(
              '*, user:user_id(email, first_name, last_name)'
          ).eq('organisation_id', org_id).execute()
          
          return {"members": result.data}
          
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  
  @router.post("/{org_id}/members")
  async def invite_member(
      org_id: str,
      request: InviteMemberRequest,
      user_id: str = Header(...)
  ):
      """Invite a new member to organisation"""
      # Check if user has admin access
      if not await check_organisation_access(user_id, org_id):
          raise HTTPException(status_code=403, detail="Access denied")
      
      try:
          db = get_db()
          
          # Check user's role
          member_result = db.table('organisation_members').select('role').eq(
              'organisation_id', org_id
          ).eq('user_id', user_id).execute()
          
          if not member_result.data or member_result.data[0]['role'] not in ['owner', 'admin']:
              raise HTTPException(status_code=403, detail="Insufficient permissions")
          
          # Find user by email
          user_result = db.table('user').select('user_id').eq(
              'email', request.email
          ).execute()
          
          if not user_result.data:
              raise HTTPException(status_code=404, detail="User not found")
          
          invited_user_id = user_result.data[0]['user_id']
          
          # Check if already a member
          existing = db.table('organisation_members').select('*').eq(
              'organisation_id', org_id
          ).eq('user_id', invited_user_id).execute()
          
          if existing.data:
              raise HTTPException(status_code=400, detail="User is already a member")
          
          # Add member
          member_data = {
              'organisation_id': org_id,
              'user_id': invited_user_id,
              'role': request.role,
          }
          
          result = db.table('organisation_members').insert(member_data).execute()
          
          # Create audit log
          await create_audit_log(
              organisation_id=org_id,
              user_id=user_id,
              action='member_invited',
              field_name='email',
              new_value=request.email,
              outcome='success'
          )
          
          return {"member": result.data[0]}
          
      except HTTPException:
          raise
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  
  @router.get("/{org_id}/member")
  async def get_member_info(
      org_id: str,
      user_id: str = Header(...)
  ):
      """Get user's membership info for an organisation"""
      try:
          db = get_db()
          result = db.table('organisation_members').select('*').eq(
              'organisation_id', org_id
          ).eq('user_id', user_id).execute()
          
          if not result.data:
              raise HTTPException(status_code=404, detail="Not a member")
          
          return result.data[0]
          
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  ```
- [ ] Create user organisations endpoint in `apps/api/app/routers/users.py`:
  ```python
  from fastapi import APIRouter, HTTPException
  from app.database import get_db
  
  router = APIRouter()
  
  @router.get("/{user_id}/organisations")
  async def get_user_organisations(user_id: str):
      """Get all organisations for a user"""
      try:
          db = get_db()
          result = db.table('organisation_members').select(
              'role, organisations(id, name, subscription_tier)'
          ).eq('user_id', user_id).execute()
          
          organisations = []
          for item in result.data:
              if item.get('organisations'):
                  org = item['organisations']
                  org['role'] = item['role']
                  organisations.append(org)
          
          return {"organisations": organisations}
          
      except Exception as e:
          raise HTTPException(status_code=500, detail=str(e))
  ```
- [ ] Update `apps/api/main.py` to include new routers:
  ```python
  from app.routers import stripe, test, organisations, users
  
  app.include_router(organisations.router, prefix="/organisations", tags=["organisations"])
  app.include_router(users.router, prefix="/users", tags=["users"])
  ```
- [ ] Create organisation switcher component in `apps/web/components/organisation-switcher.tsx`:
  ```typescript
  'use client';
  
  import { useState } from 'react';
  import { useSessionStore } from '@/lib/stores/session';
  import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuLabel,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
  } from '@/components/ui/dropdown-menu';
  import { Button } from '@/components/ui/button';
  import { Building2, ChevronDown, Plus } from 'lucide-react';
  
  export function OrganisationSwitcher() {
    const { 
      organisation_name, 
      organisations, 
      setActiveOrganisation 
    } = useSessionStore();
    const [isLoading, setIsLoading] = useState(false);
    
    const handleSwitch = async (orgId: string) => {
      setIsLoading(true);
      await setActiveOrganisation(orgId);
      setIsLoading(false);
      // Reload to ensure all data is fresh
      window.location.reload();
    };
    
    return (
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button 
            variant="outline" 
            className="w-full justify-between"
            disabled={isLoading}
          >
            <div className="flex items-center gap-2">
              <Building2 className="h-4 w-4" />
              <span className="truncate">
                {organisation_name || 'Select Organisation'}
              </span>
            </div>
            <ChevronDown className="h-4 w-4 opacity-50" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" className="w-56">
          <DropdownMenuLabel>Organisations</DropdownMenuLabel>
          <DropdownMenuSeparator />
          {organisations.map((org) => (
            <DropdownMenuItem
              key={org.id}
              onClick={() => handleSwitch(org.id)}
              className="cursor-pointer"
            >
              <Building2 className="mr-2 h-4 w-4" />
              <span className="truncate">{org.name}</span>
            </DropdownMenuItem>
          ))}
          <DropdownMenuSeparator />
          <DropdownMenuItem className="cursor-pointer">
            <Plus className="mr-2 h-4 w-4" />
            Create Organisation
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    );
  }
  ```
- [ ] Update dashboard sidebar to include organisation switcher:
  ```typescript
  // In apps/web/app/dashboard/_components/dashboard-side-bar.tsx
  // Add import at top
  import { OrganisationSwitcher } from '@/components/organisation-switcher';
  
  // Add after the logo/title section:
  <div className="px-3 py-2">
    <OrganisationSwitcher />
  </div>
  <Separator className="my-2" />
  ```
- [ ] Test organisation switching functionality
- [ ] Verify session persists across tabs

## Phase 3.3: Xero OAuth Integration

### Objective
Implement Xero OAuth authentication flow for connecting accounting software to organisations.

### Tasks
- [ ] Set up Xero app credentials:
  ```
  # Add to apps/api/.env
  XERO_CLIENT_ID=your_xero_client_id
  XERO_CLIENT_SECRET=your_xero_client_secret
  XERO_REDIRECT_URI=http://localhost:8000/xero/callback
  ```
- [ ] Update `apps/api/requirements.txt`:
  ```
  xero-python==3.3.0
  aiohttp==3.9.1
  ```
- [ ] Create Xero configuration in `apps/api/app/config.py`:
  ```python
  # Add to Settings class
  XERO_CLIENT_ID: str
  XERO_CLIENT_SECRET: str
  XERO_REDIRECT_URI: str = "http://localhost:8000/xero/callback"
  ```
- [ ] Create Xero service in `apps/api/app/services/xero_service.py`:
  ```python
  from xero_python.api_client import ApiClient
  from xero_python.api_client.configuration import Configuration
  from xero_python.api_client.oauth2 import OAuth2Token
  from xero_python.accounting import AccountingApi
  from xero_python.identity import IdentityApi
  from app.config import settings
  from app.database import get_db
  import secrets
  import base64
  from typing import Optional, Dict, Any
  
  class XeroService:
      def __init__(self):
          self.client_id = settings.XERO_CLIENT_ID
          self.client_secret = settings.XERO_CLIENT_SECRET
          self.redirect_uri = settings.XERO_REDIRECT_URI
          self.scope = "openid profile email accounting.transactions accounting.contacts accounting.settings offline_access"
      
      def get_authorization_url(self, state: str) -> str:
          """Generate Xero OAuth authorization URL"""
          auth_url = (
              f"https://login.xero.com/identity/connect/authorize?"
              f"response_type=code&"
              f"client_id={self.client_id}&"
              f"redirect_uri={self.redirect_uri}&"
              f"scope={self.scope}&"
              f"state={state}"
          )
          return auth_url
      
      async def exchange_code_for_token(self, code: str) -> Dict[str, Any]:
          """Exchange authorization code for access token"""
          api_client = ApiClient(
              Configuration(
                  oauth2_token=OAuth2Token(
                      client_id=self.client_id,
                      client_secret=self.client_secret
                  )
              )
          )
          
          token = api_client.get_client_credentials_token()
          return {
              'access_token': token['access_token'],
              'refresh_token': token.get('refresh_token'),
              'expires_in': token.get('expires_in'),
              'scope': token.get('scope')
          }
      
      async def get_tenants(self, access_token: str) -> list:
          """Get available Xero tenants for the authenticated user"""
          api_client = ApiClient(
              Configuration(
                  access_token=access_token
              )
          )
          
          identity_api = IdentityApi(api_client)
          tenants = identity_api.get_connections()
          
          return [
              {
                  'tenant_id': t.tenant_id,
                  'tenant_name': t.tenant_name,
                  'tenant_type': t.tenant_type
              }
              for t in tenants
          ]
      
      async def store_xero_connection(
          self,
          organisation_id: str,
          tenant_id: str,
          access_token: str,
          refresh_token: str,
          expires_in: int
      ):
          """Store Xero connection details securely"""
          db = get_db()
          
          # In production, encrypt these tokens
          connection_data = {
              'organisation_id': organisation_id,
              'xero_tenant_id': tenant_id,
              'access_token': access_token,  # Should be encrypted
              'refresh_token': refresh_token,  # Should be encrypted
              'expires_at': expires_in  # Convert to timestamp
          }
          
          # Store in a secure table (create xero_connections table in migration)
          # For now, update organisation with tenant_id
          db.table('organisations').update({
              'xero_tenant_id': tenant_id
          }).eq('id', organisation_id).execute()
  ```
- [ ] Create Xero OAuth router in `apps/api/app/routers/xero.py`:
  ```python
  from fastapi import APIRouter, HTTPException, Header, Query
  from fastapi.responses import RedirectResponse
  from app.services.xero_service import XeroService
  from app.config import settings
  import secrets
  import json
  import base64
  
  router = APIRouter()
  xero_service = XeroService()
  
  # Temporary storage for OAuth state (use Redis in production)
  oauth_states = {}
  
  @router.get("/connect")
  async def start_xero_connection(
      organisation_id: str = Query(...),
      user_id: str = Header(...)
  ):
      """Start Xero OAuth flow"""
      # Generate secure state parameter
      state = secrets.token_urlsafe(32)
      
      # Store state with org and user info
      oauth_states[state] = {
          'organisation_id': organisation_id,
          'user_id': user_id
      }
      
      # Get authorization URL
      auth_url = xero_service.get_authorization_url(state)
      
      return {
          'auth_url': auth_url,
          'state': state
      }
  
  @router.get("/callback")
  async def xero_callback(
      code: str = Query(...),
      state: str = Query(...)
  ):
      """Handle Xero OAuth callback"""
      # Verify state
      if state not in oauth_states:
          raise HTTPException(status_code=400, detail="Invalid state parameter")
      
      state_data = oauth_states.pop(state)
      organisation_id = state_data['organisation_id']
      user_id = state_data['user_id']
      
      try:
          # Exchange code for token
          token_data = await xero_service.exchange_code_for_token(code)
          
          # Get available tenants
          tenants = await xero_service.get_tenants(token_data['access_token'])
          
          if not tenants:
              raise HTTPException(status_code=400, detail="No Xero organisations found")
          
          # For MVP, use the first tenant
          tenant = tenants[0]
          
          # Store connection
          await xero_service.store_xero_connection(
              organisation_id=organisation_id,
              tenant_id=tenant['tenant_id'],
              access_token=token_data['access_token'],
              refresh_token=token_data['refresh_token'],
              expires_in=token_data['expires_in']
          )
          
          # Redirect to success page
          return RedirectResponse(
              url=f"{settings.FRONTEND_URL}/dashboard/settings?xero=connected"
          )
          
      except Exception as e:
          # Redirect to error page
          return RedirectResponse(
              url=f"{settings.FRONTEND_URL}/dashboard/settings?xero=error&message={str(e)}"
          )
  
  @router.get("/status/{organisation_id}")
  async def get_xero_status(
      organisation_id: str,
      user_id: str = Header(...)
  ):
      """Check if organisation has Xero connected"""
      from app.utils.database_helpers import check_organisation_access
      
      if not await check_organisation_access(user_id, organisation_id):
          raise HTTPException(status_code=403, detail="Access denied")
      
      db = get_db()
      result = db.table('organisations').select('xero_tenant_id').eq(
          'id', organisation_id
      ).execute()
      
      if result.data and result.data[0].get('xero_tenant_id'):
          return {
              'connected': True,
              'tenant_id': result.data[0]['xero_tenant_id']
          }
      
      return {'connected': False}
  
  @router.post("/disconnect/{organisation_id}")
  async def disconnect_xero(
      organisation_id: str,
      user_id: str = Header(...)
  ):
      """Disconnect Xero from organisation"""
      from app.utils.database_helpers import check_organisation_access, create_audit_log
      
      if not await check_organisation_access(user_id, organisation_id):
          raise HTTPException(status_code=403, detail="Access denied")
      
      db = get_db()
      db.table('organisations').update({
          'xero_tenant_id': None
      }).eq('id', organisation_id).execute()
      
      await create_audit_log(
          organisation_id=organisation_id,
          user_id=user_id,
          action='xero_disconnected',
          outcome='success'
      )
      
      return {'status': 'disconnected'}
  ```
- [ ] Update main.py to include Xero router:
  ```python
  from app.routers import stripe, test, organisations, users, xero
  
  app.include_router(xero.router, prefix="/xero", tags=["xero"])
  ```
- [ ] Create Xero connection UI in `apps/web/app/dashboard/settings/page.tsx`:
  ```typescript
  'use client';
  
  import { useState, useEffect } from 'react';
  import { useSession } from '@/lib/hooks/use-session';
  import { Button } from '@/components/ui/button';
  import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
  import { useSearchParams } from 'next/navigation';
  import { toast } from 'sonner';
  
  export default function SettingsPage() {
    const { organisation } = useSession();
    const [xeroConnected, setXeroConnected] = useState(false);
    const [loading, setLoading] = useState(false);
    const searchParams = useSearchParams();
    
    useEffect(() => {
      // Check for Xero callback
      const xeroStatus = searchParams.get('xero');
      if (xeroStatus === 'connected') {
        toast.success('Xero connected successfully');
        checkXeroStatus();
      } else if (xeroStatus === 'error') {
        toast.error('Failed to connect Xero');
      }
    }, [searchParams]);
    
    useEffect(() => {
      if (organisation.id) {
        checkXeroStatus();
      }
    }, [organisation.id]);
    
    const checkXeroStatus = async () => {
      if (!organisation.id) return;
      
      try {
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/xero/status/${organisation.id}`,
          {
            headers: {
              'user-id': localStorage.getItem('user_id') || '',
            },
          }
        );
        
        if (response.ok) {
          const data = await response.json();
          setXeroConnected(data.connected);
        }
      } catch (error) {
        console.error('Error checking Xero status:', error);
      }
    };
    
    const connectXero = async () => {
      setLoading(true);
      try {
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/xero/connect?organisation_id=${organisation.id}`,
          {
            headers: {
              'user-id': localStorage.getItem('user_id') || '',
            },
          }
        );
        
        if (response.ok) {
          const data = await response.json();
          window.location.href = data.auth_url;
        }
      } catch (error) {
        toast.error('Failed to start Xero connection');
      } finally {
        setLoading(false);
      }
    };
    
    const disconnectXero = async () => {
      setLoading(true);
      try {
        const response = await fetch(
          `${process.env.NEXT_PUBLIC_API_URL}/xero/disconnect/${organisation.id}`,
          {
            method: 'POST',
            headers: {
              'user-id': localStorage.getItem('user_id') || '',
            },
          }
        );
        
        if (response.ok) {
          setXeroConnected(false);
          toast.success('Xero disconnected');
        }
      } catch (error) {
        toast.error('Failed to disconnect Xero');
      } finally {
        setLoading(false);
      }
    };
    
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-3xl font-bold">Settings</h1>
          <p className="text-muted-foreground">
            Manage your organisation settings and integrations
          </p>
        </div>
        
        <Card>
          <CardHeader>
            <CardTitle>Xero Integration</CardTitle>
            <CardDescription>
              Connect your Xero account to sync invoices and payments
            </CardDescription>
          </CardHeader>
          <CardContent>
            {xeroConnected ? (
              <div className="space-y-4">
                <p className="text-sm text-green-600">
                  ✓ Xero is connected
                </p>
                <Button 
                  onClick={disconnectXero} 
                  variant="outline"
                  disabled={loading}
                >
                  Disconnect Xero
                </Button>
              </div>
            ) : (
              <div className="space-y-4">
                <p className="text-sm text-muted-foreground">
                  Connect your Xero account to start syncing data
                </p>
                <Button 
                  onClick={connectXero}
                  disabled={loading}
                >
                  Connect to Xero
                </Button>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    );
  }
  ```
- [ ] Test complete Xero OAuth flow
- [ ] Verify connection status is saved
- [ ] Test disconnect functionality

## Verification Checklist
- [ ] Zustand store is working and persisting data
- [ ] Session provider hydrates on app load
- [ ] Organisation switcher displays all user organisations
- [ ] Switching organisations updates the UI
- [ ] Cross-tab organisation changes trigger reload
- [ ] API endpoints for organisations are working
- [ ] Users can be invited to organisations
- [ ] Xero OAuth flow completes successfully
- [ ] Xero connection status is displayed correctly
- [ ] Audit logs are created for key actions

## Next Steps
Once Phase 3 is complete, proceed to Phase 4: RemitMatch Core Features, which will implement the file upload system, remittance processing, and UI components.