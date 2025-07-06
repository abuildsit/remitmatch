# RemitMatch - Functional Specification

## Purpose

RemitMatch is a web application that streamlines the reconciliation of remittance advice PDFs (or other formats)with invoice data from accounting software. It reduces manual data entry by extracting invoice/payment details from remittance documents and matching them against accounting records.

---

## Core Problem

Companies receive remittance advices (usually PDFs), often covering multiple invoices. Matching these to invoices in accounting software (e.g., Xero) is usually manual and time-consuming.

---

## MVP Features

### Functional Overview

1. **Authentication**

- OAuth login via Xero
- Standard login/register

2. **Organisation Setup** 

**✅ Confirmed Behavior**: Users land on "Connect to Xero" screen immediately upon signup.

- Upon successful connection, the organisation is created using the organisation name from Xero.
- **✅ Confirmed**: Organisation and tenant information is stored in Supabase database.
- The system checks for existing organisations with the same Xero tenant ID to avoid duplication.
- If an organisation with that Xero account already exists, the user is shown a message: "This organisation is already registered in RemitMatch."
- The user is given the option to send an access request email to the primary contact of the organisation.
- A new role type, **Organisation Owner**, is introduced. This user is the primary contact for the organisation and receives administrative notifications, including:
  - Access requests
  - Billing notices
  - System-wide alerts (e.g. data export or deletion requests)
- Select which bank accounts to include in RemitMatch as available to map payments against.
- One of these will be marked as the default account for payment mapping

**Session Metadata Storage**: After successful connection, the following metadata is stored in the client session (as defined in Client Session Model section):
- user_id, user_email, user_display_name
- organisation_id, organisation_name  
- role, subscription_tier
- org_membership_ids (for organisation switching)

3. **Remittance Management**

**✅ Confirmed Upload Flow**:
- **✅ Confirmed**: File goes directly to Supabase Storage upon upload
- **✅ Confirmed**: Supabase Edge Function triggered via `storage.onUpload` event
- **✅ Confirmed**: Edge Function calls backend `processRemittance()` function
- Extract payment data (invoice #s, amounts paid)
- Match data against Xero invoice data
- **✅ Confirmed Manual Override & Approval Flow**:
  - Users can select from a dropdown of all open invoices
  - Users can edit the extracted payment amount per invoice
  - The top-level remittance amount is always the sum of invoice lines and cannot be overridden
  - **✅ Confirmed**: Two buttons available: "Save Manual Changes" and "Save + Approve"
  - **✅ Confirmed**: Backend uses single atomic `approve_remittance()` endpoint
  - **✅ Confirmed**: Optimistic UI updates status locally first, real sync is backgrounded
  - Once a remittance is approved, no further changes can be made (see Unapproval Logic below)
  - Approved remittances are pushed to Xero with a status of 'Unreconciled'
  - Final status is 'Reconciled' once payment is confirmed in Xero
  - Reconciliation status is detected via polling Xero daily at the start of each day
  - **✅ Confirmed**: Global "Refresh" button on remittance list for manual Xero sync
  - **✅ Confirmed**: Per-remittance "Retry" button for AI extraction retry
  - **Each remittance will store a single AI-generated confidence score (not shown in the UI).** This score reflects the overall confidence of the extraction process across the remittance. It is not currently used in the user workflow but may later support features like auto-approval of high-confidence remittances (e.g. >95%). Confidence is stored for internal monitoring and potential future automation only.
- Soft delete behaviour:
  - Users can soft delete a remittance (logically hide it)
  - Deleted remittances are hidden from the UI
  - **Deletion is not allowed** if the remittance is in `All payments matched - Awaiting Approval`, `Exported to Xero - Unreconciled`, or `Exported to Xero - Reconciled` status
    - Users must unapprove first before deletion

4. **Remittance State Machine**

- `Uploaded` → `Data Retrieved`
- `Data Retrieved` → `All payments matched - Awaiting Approval` / `Error - Payments Unmatched`
- `All payments matched - Awaiting Approval` → `Exported to Xero - Unreconciled`
- `Exported to Xero - Unreconciled` → `Exported to Xero - Reconciled`
- `Error - Payments Unmatched` → `All payments matched - Awaiting Approval` (after manual override)
- `Error - Payments Unmatched` → `Data Retrieved` (retry AI extraction)
- Failed Xero export → `Export Failed`
- Any status → `Soft Deleted` (logical deletion)

5. **Unapproval Logic**

Once a remittance is approved, it enters the status `Exported to Xero - Unreconciled` and a payment is created in Xero.

**Unapproval is allowed under the following conditions:**

- **Who can unapprove:** Any user with role **Admin** or **User**.
- **When:**
  - The remittance is in status `Exported to Xero - Unreconciled`.
  - The corresponding payment in Xero **has not been reconciled**.
  - The payment in Xero **can be successfully deleted** via API.

If these conditions are met:

- The payment is deleted in Xero.
- The remittance reverts to the prior status:
  - `All payments matched - Awaiting Approval` if auto-matched
  - `All payments matched - Awaiting Approval` if manually adjusted
- A new audit log entry is created for the unapproval.

If unapproval is blocked:

- The user is shown a message explaining the reason (e.g. "This payment has already been reconciled in Xero. Please unreconcile the payment in Xero before trying again.")
- No state change occurs in RemitMatch.

**Audit Logging:**

- Every unapproval attempt is logged, including:
  - User ID
  - Timestamp
  - Outcome: `success` or `rejected`
  - Reason if rejected (e.g. "payment already reconciled")

**Sync Monitoring: New Status**

- Add status `Export Failed`: Indicates that the payment in Xero has diverged from the approved remittance (e.g. amount, invoice mapping, or deletion).
- This is triggered via webhook or periodic sync check.
- Remittance is flagged for review.
- Blocks further approval/unapproval until resolved or reset.

6. **Chart of Accounts Integration**

- Import bank accounts from Xero
- Select default payment account per organisation
- Allow overrides per remittance

7. **Organisation & User Management**

- Users belong to organisations - which are the primary organising structure of the app
- Users can belong to multiple organisations
- Organisation invites via email
- Allow switching between organisations
- While logged in as a user in an organisation, users can add others by entering their email address and selecting a role
- User roles included in MVP:
  - Organisation Owner: full access including billing, user management, unapproval, and receiving administrative emails
  - Admin: full access to app functionality including inviting users and unapproving remittances
  - User: can upload, reconcile, and unapprove remittances, but cannot invite users
  - Auditor: can only view remittance data and audit logs

8. **Client Session Model**

To support a smooth multi-tenancy experience, RemitMatch maintains a persistent client-side session store that includes key context:

- user_id: Current logged-in user
- user_email, user_display_name
- organisation_id, organisation_name
- role: User's role in the active organisation
- subscription_tier: Cached subscription level, used for UI restrictions
- org_membership_ids: Used to support organisation switching

**✅ Confirmed Implementation Strategy**

**✅ Confirmed Zustand Store Shape**:
```typescript
type SessionState = {
  user_id: string;
  user_email: string;
  organisation_id: string;
  organisation_name: string;
  role: "owner" | "admin" | "user" | "auditor";
  subscription_tier: "free" | "business" | "pro" | "max";
  active_remittance_id: string | null;
  org_membership_ids: string[]; // for switching orgs
  setActiveOrganisation: (orgId: string) => void;
};
```

This session context is hydrated after login or org switch and remains in memory for the duration of the session. Recommended options:

- **✅ Confirmed**: Zustand: Lightweight, reactive store for easy cross-component access
- React Context: For simpler apps with fewer dependencies
- React Query: Can be used in combination to manage stale/fresh data control

Session state is used to:

- Gate UI access (e.g. Admin-only actions)
- Determine current organisation context across pages
- Avoid passing data through URL parameters
- **✅ Confirmed**: Track active remittance selection across views

All backend or Supabase calls can leverage this session data to ensure proper authorisation and UX continuity.

**🧠 Tab Switch Security Issue**

**✅ Confirmed Security Strategy**: To prevent cross-tab state conflict:

- **✅ Confirmed**: Backend routes must validate the `organisation_id` from session and compare it to what's being acted on
- **✅ Confirmed**: Every `POST /remittance/:id/*` call should verify that the remittance belongs to the active org of the session
- **🛡️ Best practice**: All updates go via backend, even if Supabase is used directly for reads

9. **UI Interaction and State Management**

To ensure seamless transitions and accurate updates across screens, RemitMatch uses a shared in-memory state model to persist and propagate remittance data during user interaction.

**Navigation Model**
- UI state (e.g. selected remittance, filters, scroll position) is maintained in memory
- No query parameters or route chaining are used to pass state between views

10. **AI Processing Workflow**

- After a remittance is uploaded, the system calls a single `process_remittance(fileUrl)` function to initiate extraction.
- This function is the entry point for the AI matching process and allows backend logic to be updated without requiring frontend changes.
- Backend could radically change, but this allows maximum swapout.
  - e.g. The AI first approach could be replaced by a function to extract text via OCR, etc.
  - The goal is to allow us to iterate on the backend without impacting the rest of the app.
- For now, the primary method uses OpenAI's Assistant API with a defined system prompt.
- The output must be returned in the expected JSON format, including a `confidence` field:
- WIll likely later implement logic to try a second approach if the confidence is below a threshold.
  - And opitonally allow the user to turn on auto-approving remittances with confidence above a threshold

```json
{
  "Date": "[Date]",
  "TotalAmount": [Total_Amount],
  "PaymentReference": "[Payment_Reference_or_None]",
  "Payments": [
    {
      "InvoiceNo": "[InvoiceNo1]",
      "PaidAmount": [Paid_Amount1]
    }
    {
      "InvoiceNo": "[InvoiceNo2]",
      "PaidAmount": [Paid_Amount2]
    }
  ],
  "confidence": "[% confidence that the correct information has been extracted]"
}
```

- If AI returns default or empty JSON, retry with alternate method
- If extraction fails, the system will automatically queue a retry
- Include 'Retry' button in UI to manually trigger fallback or reprocessing

12. **Audit Log**

- Maintain a full history of all changes made to each remittance
- Log includes:
  - User who made the change
  - Timestamp of change
  - Type of action (e.g. edit, approval, unapproval, sync attempt)
  - Field changed (if applicable)
  - Original value → New value (for field-level changes)
  - Outcome (e.g. success, error)
- Include status changes such as:
  - Initial match complete
  - Approved
  - Soft delete (logical removal, not physical)
  - Error states
- All users can view the audit log on each remittance

13. **Xero Sync Failure Handling**

- **Sync Failure Status:**

  - Add a new remittance status `Export Failed`
  - Indicates the attempt to create a payment in Xero was unsuccessful (e.g. API error, validation error, network failure)
  - Remittance remains in `All payments matched - Awaiting Approval` state
  - Display an error message in the remittance detail view
  - Show a badge/tag in the remittance list

- **Retry Strategy:**

  - User can manually retry the sync using a “Retry Xero Export” button
  - Retry attempts are logged and optionally rate-limited to avoid abuse or repeated failure

- **Audit Trail for Sync Attempts:**

  - Log all sync attempts (success or failure)
  - Record:
    - Timestamp
    - Outcome (success or error)
    - Xero API response (sanitised)
    - User ID if manually triggered

- **User Feedback:**

  - Remittances with sync failures appear in a dedicated summary on the Dashboard
  - Badge appears on remittance in list view to highlight error state

14. **Subscription Management**

- Integrated with Stripe
- Managed at the organisation level
- Users without an active subscription cannot access core features
- Subscription plans (indicative):
  - **Free Tier**: Up to 5 remittances per month
  - **Business**: \$15/month for 30 remittances
  - **Pro**: \$30/month for 120 remittances
  - **Max**: \$50/month for 250 remittances
- Subscription usage is tracked per organisation
- Subscription enforcement includes soft limits with upgrade prompts and hard caps beyond threshold
- Future implementation will include rate-limiting protections to avoid abuse (e.g. upload spam, excessive retries)
- Will need to manage rate limiting to prevent abuse and protect API cost


15. - Auth:
- App to use Email, Google, and Xero OAuth
- auth.users to map to public.profiles through a public.auth_link_table

## Technology Stack & Architecture

### Frontend

- **Framework**: Next.js
- **Hosting**: Vercel
- **State Management**: Zustand (with optional React Context/React Query integration)
- **Authentication**: Supabase Auth
- **Storage**: Supabase Storage (PDFs and AI outputs)
- **API Communication**: Supabase client (direct) or backend API where appropriate

### Backend

- **Framework**: FastAPI (Python)
- **Hosting**: Render.com
- **Responsibilities**:
  - Xero API polling (daily syncs, scheduled jobs)
  - AI remittance processing (OpenAI Assistant API)
  - Validation and sync logic (approval, unapproval, reconciliation)
  - Secure interaction with Supabase
  - **Scheduled Tasks**: Daily background job at 3:00 AM to extract invoice details from connected accounting software (Xero) for all organisations
- **✅ Confirmed API Endpoints**:
  - `processRemittance()` - Called by Supabase Edge Function
  - `approve_remittance()` - Atomic approval operation
  - `/dashboard/summary` - Single endpoint returning all dashboard counts

**🧩 API Structure & Routing**

**✅ Confirmed Read/Write Split**:

**🔁 Read / Supabase (client-safe)**:
These fetch data directly via React Query:

- `GET /remittances` (list view, filters, pagination)
- `GET /remittance/:id` (detail view)
- `GET /dashboard/summary`

**⚙️ Write / Backend**:
All modifying actions are routed through backend for:
- Multi-tenant validation
- Security
- Cross-service logic (e.g., Xero integration)

- `POST /remittance/:id/save-overrides`
- `POST /remittance/:id/approve`
- `POST /remittance/:id/unapprove`
- `POST /remittance/:id/retry-ai`
- `POST /xero/sync-all` (manual refresh)

**🔍 Error Handling: UX Strategy**

**✅ Confirmed Error Handling Behavior**:

| Scenario | Backend Behaviour | Frontend Status Update |
|----------|------------------|----------------------|
| Export to Xero fails | Return 500, update status to `Export Failed` | Show badge: Export Failed |
| Retry AI fails again | Update status to `Error - Payments Unmatched` | Show badge: Needs Manual Match |
| Manual override saved | Update remittance, recalculate matching, return state | Show badge: Saved - Awaiting Approval |
| Xero refresh fails | Return last-known state (fallback), log warning | No visual error shown |

**✅ Confirmed**: All changes to remittance status should be clearly reflected in the table row and persisted to Supabase.

---

## Session + Organisation Context Handling

This section outlines the strategy for managing user sessions, organisation context, and multi-tenant safety across the RemitMatch application.

### Goals

- Avoid cross-organisation state confusion (especially in multi-tab workflows)
- Ensure all backend operations are performed within an authorised, validated organisation context
- Prevent issues like approving a remittance in Org A while viewing Org B

### Client Session Model (Frontend)

Implemented using Zustand. The in-memory shape:

```typescript
{
  user_id: string;
  organisation_id: string;
  role: "owner" | "admin" | "user" | "auditor";
  subscription_tier: string;
  active_remittance_id: string | null;
}
```

**Initialisation**
- Hydrated on app load from `/me` endpoint
- React hook (`useSessionStore`) reads and sets the session

### Cross-tab Handling

- Use storage event listener on `localStorage` to detect `active_organisation` change
- Prompt reload or rehydrate session on mismatch

### Organisation Display in UI

- A persistent, visible indicator of the current active organisation must be shown in the application (e.g. in the sidebar header, as shown in UI designs)
- Must update immediately if the user changes organisation

### Backend Auth + Org Context

Every protected route must validate the user's active organisation explicitly:

**Example: Approve Remittance**

```
POST /api/remittance/:id/approve
{
  organisation_id: "org_123"
}
```

**Validation Logic**

```typescript
const user = await getCurrentUserFromToken(req)

if (!userHasAccessToOrg(user.id, req.body.organisation_id)) {
  return res.status(403).json({ error: "Access denied to organisation" })
}

const remittance = await db.remittances.findById(req.params.id)
if (remittance.organisation_id !== req.body.organisation_id) {
  return res.status(403).json({ error: "Remittance does not belong to organisation" })
}
```

### Centralised Org Validation Utility (Backend)

```typescript
export async function assertValidOrgContext(user_id: string, organisation_id: string) {
  const membership = await db.organisation_members.findFirst({
    where: { user_id, organisation_id }
  })

  if (!membership) {
    throw new Error("Invalid organisation context")
  }
}
```

### Remittance Status Lifecycle (Enum)

To standardise remittance handling, statuses are centrally managed as an enum:

```typescript
export type RemittanceStatus =
  | "Uploaded"
  | "Data Retrieved"
  | "All payments matched - Awaiting Approval"
  | "Error - Payments Unmatched"
  | "Exported to Xero - Unreconciled"
  | "Exported to Xero - Reconciled"
  | "Export Failed"
  | "Soft Deleted";
```

These values are used across:

- UI filters
- Table row display
- API status transitions
- Matching logic + retry flags

### Remittance Lines Table

Each remittance line item (representing one invoice from a remittance) tracks both AI-extracted values and optional manual overrides.

```sql
CREATE TABLE remittance_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  remittance_id UUID NOT NULL REFERENCES remittances(id),

  invoice_number TEXT NOT NULL,              -- Extracted from AI
  ai_paid_amount NUMERIC NOT NULL,           -- From AI extraction
  manual_paid_amount NUMERIC,                -- Optional user override

  ai_invoice_id UUID REFERENCES invoices(id),      -- Matched by backend logic
  override_invoice_id UUID REFERENCES invoices(id), -- Set by user manually, if overridden

  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

**Behaviour**

- If `override_invoice_id` is NULL, use `ai_invoice_id`
- If `manual_paid_amount` is NULL, use `ai_paid_amount`
- Enables accurate rollback after unapproving a remittance
- Supports full auditability and visibility into overrides

### Benefits

- Hardens multi-tenant boundaries
- Ensures only authorised users act within scope
- Prevents silent data corruption due to stale tabs or invalid session state
- Supports organisation switching while keeping backend in sync

### Notes

- All writes must include `organisation_id`
- All backend routes should validate session tokens + organisation context
- We may consider also encoding the active `organisation_id` into the JWT in future, for additional validation

### Future Improvements

- Add visual indicator of current organisation in UI (Implemented in MVP — see sidebar)
- Persist last selected organisation to localStorage and Supabase profile
- Prevent navigating to pages if user's active org isn't permitted for that resource

---

### Shared Types & Schema Strategy

- **Schema Format**: JSON Schema (stored in `packages/shared/schemas/`)
- **Purpose**: Defines the contract for remittance objects shared across frontend and backend
- **Frontend Use**: TypeScript types generated using `json-schema-to-typescript`
- **Backend Use**: Loaded into FastAPI using `pydantic.create_model_from_json_schema()`
- **Benefit**: Ensures a single source of truth for request/response structures, reducing desynchronisation risk

### Database

- **Platform**: Supabase (PostgreSQL)
- **Security**: Row-Level Security (RLS)
- **Usage tracking**: Tracked via backend events and scheduled summaries

### Domains

- Primary domain: `remitmatch.com`
  - `app.remitmatch.com` → Frontend (Vercel)
  - `api.remitmatch.com` → Backend (Fly.io with FastAPI)

---

## Design System Decisions

- **Styling Framework**: Tailwind CSS (utility-first)
- **Component Library**: shadcn/ui
  - Provides accessible, clean components
  - Fully customisable with Tailwind
- **Dark Mode**: Not included in MVP
- **Design Approach**: Code-first prototyping (no Figma dependency)
- **Typography & Spacing**:
  - No hardcoded values in components or screens
  - Use centralised Tailwind tokens for font sizes, spacing, colours
  - Optionally extract base theme into `packages/ui/theme.ts` for clarity and control

**🎨 Design System Integration (Frontend)**

**✅ Confirmed Component Structure**:
All components will use centralised design primitives:

```tsx
<Text size="sm" variant="muted" />
<Button variant="primary" size="md" />
<Badge variant="error" /> // status indicators
```

**✅ Confirmed**: No text sizes, colours, paddings hardcoded into screens.

**✅ Confirmed**: Tailwind + custom theme tokens via a design system layer.

**✅ Confirmed Status Badge Mapping**:
Status → badge mapping defined centrally, e.g.:

```typescript
{
  "All payments matched - Awaiting Approval": "info",
  "Exported to Xero - Unreconciled": "success",
  "Exported to Xero - Reconciled": "success", 
  "Export Failed": "error",
  "Error - Payments Unmatched": "warning",
  "Data Retrieved": "info",
  "Uploaded": "info",
  "Soft Deleted": "muted",
}
```

---

## Monorepo Structure

A monorepo is used to unify development across frontend, backend, and shared modules.

### Suggested Folder Layout

```
remitmatch/
├── apps/
│   ├── web/        # Next.js frontend (Vercel)
│   └── api/        # FastAPI backend (Fly.io)
├── packages/
│   ├── shared/     # Shared types, constants, schema definitions
│   └── config/     # Shared ESLint, Prettier, TS config
├── .github/        # CI/CD workflows
├── .env
├── turbo.json      # (if using Turborepo)
├── package.json
```

### Recommended Tools

- **Turborepo**: For task orchestration and cache
- **pnpm**: Package manager supporting workspaces
- **GitHub Actions**: CI/CD per app (deploy frontend/backend separately)
- **Docker**: For FastAPI packaging and deployment

---

## Deployment

### Frontend (Vercel)

- Hosted via Vercel’s optimised platform for Next.js
- Integrated with Supabase client for database access
- Calls backend API only where logic must be secured or async (e.g. Xero export)

### Backend (Render.com)

- Hosts FastAPI app
- Handles scheduled polling (daily invoice status syncs)
- Performs AI processing tasks
- Exposes protected API endpoints
- Can be scaled independently
- **Daily Scheduled Tasks**: 3:00 AM job to sync invoice data from Xero for all organisations

### Domain Setup

- Use `remitmatch.com` as root
  - Subdomain `app.remitmatch.com` for frontend (CNAME to Vercel)
  - Subdomain `api.remitmatch.com` for backend (CNAME to Render.com IP/hostname)
- SSL provided via Vercel and Render.com automatically

---

## Cost Considerations (Startup Phase)

| Component        | Platform        | Est. Monthly Cost (AUD)    |
| ---------------- | --------------- | -------------------------- |
| Frontend         | Vercel Free/Pro | \$0 – \$20                 |
| Backend API      | Render.com      | Free – \$7                 |
| Database         | Supabase Pro    | \$30 – \$70                |
| AI API (OpenAI)  | Usage based     | \~\$0.10–\$0.30/remittance |
| Stripe/Xero APIs | Free tiers      | \$0                        |
| Domain           | Namecheap       | \~\$15/year                |

This keeps monthly infra costs under \$100 while maintaining flexibility and scalability.

---


## Planned Features (Post-MVP)

1. **Email Submission of Remittances**

   - Each organisation is assigned a unique upload email address, using `+aliases` or sub-addressing.
   - Users can configure which sender email addresses are allowed to submit remittances via email.
   - Files sent to this address are processed and appear alongside manually uploaded remittances in the same workflow.
   - Audit logs will show the sender email address and timestamp.
   - Failed or unprocessable emails are only surfaced in the UI (no outbound failure email notifications in MVP).

2. **Daily Summary Notifications**

   - Optional email alerts summarising remittance issues per organisation:
     - Unmatched invoices
     - Failed extractions
     - Pending approvals
   - Configurable per user.

## UI Pages

### 1. Dashboard

**✅ Confirmed API Strategy**: Single `/dashboard/summary` endpoint

- Summary view:
  - **✅ Confirmed**: `unmatched_remittances_count` - Remittances with errors or unmatched invoices
  - **✅ Confirmed**: `awaiting_approval_count` - Awaiting approval remittances
  - **✅ Confirmed**: `reconciled_count` - Unreconciled remittances
  - **✅ Confirmed**: `failed_ai_count` - Remittances with processing failures

### 2. Remittances

**✅ Confirmed List View**:
- **✅ Confirmed**: Infinite scroll implementation using React Query
- Columns: Status, Date Added, Payment Date, Payment Amount, Reference, # Invoices
- Filters: Status, Date, etc.
- Controls: Upload, **✅ Confirmed**: Global "Refresh" button for Xero sync

**✅ Confirmed Detail View**:
- **✅ Confirmed**: PDF fetched when remittance is selected
- **✅ Confirmed**: All detail info comes from cached memory data (no additional backend calls)
- PDF viewer (left)
- Payment info (top-right): Status, Date, Amount, Reference
- Invoice mapping table (bottom-right):
  - Extracted Invoice #, Extracted Payment Amount, Extracted Payment Reference
  - Matched Invoice #, Total Invoice Value, Amount Outstanding
  - Manual override dropdowns
  - Diff between extracted and overridden values
  - Link to view audit log for the remittance

### 3. Auth Pages

- Login
- Register (triggers organisation setup if orphaned)

### 4. Organisation Settings

- Integrations: Connect to Xero
- Chart of Accounts: Select default payment account
- Members: Invite/manage users
- Subscription: Manage billing via Stripe

### 5. User Settings

- Placeholder for personal settings

## Navigation

- Sidebar or top navigation (to be confirmed)
- Org switcher for users in multiple organisations
- Main items: Dashboard, Remittances, Organisation Settings, Account Settings

## Primary Use Cases

- Upload and reconcile remittances
- Confirm payments and sync with Xero
- Manage organisations and settings
- Retry extraction logic when needed
- Notify users of reconciliation issues
- Maintain full audit history of remittance activity
- Manage subscriptions at the organisation level

## Tools Recommended for Design

- **Whimsical** – for flowcharts, state diagrams, and journey maps
- **Figma** – for wireframes and UI mockups

## Supabase Implementation

### Storage Path Structure

Files uploaded to Supabase storage will follow this path structure:

```
/{organisation.id}/{remittance.id}/{file.id or filename.pdf}
```

- Ensures clear hierarchical organisation
- Simplifies access control and cleanup operations
- Supports potential for multiple files per remittance (e.g. multi-page scans, separate images)
- AI-generated output (e.g. JSON) may also be stored alongside PDFs in the same directory

### RLS (Row-Level Security) Strategy

- **Tables:**

  - `organisations`
  - `organisation_members` (`user_id`, `organisation_id`)
  - `remittances` (`id`, `organisation_id`, ...)
  - `files` (`id`, `remittance_id`, `organisation_id`, `path`, ...)

- **RLS Policy Example:**

```sql
USING (
  EXISTS (
    SELECT 1 FROM organisation_members
    WHERE organisation_id = files.organisation_id
    AND user_id = auth.uid()
  )
)
```

- Users can only access files that belong to organisations they are members of
- File paths must remain immutable and not user-controlled
- Signed URLs can be used for secure file access in the frontend

## Key Risks and Considerations

### AI Extraction Reliability

- Manual override required for non-extractable data
- Ensure overrides are clear, auditable, and limited to invoice-level detail
- Confidence score to be included per extracted item (hidden from user)

### Sync with Xero

- Critical to define a complete failure-handling strategy for sync operations
- Must handle cases like:
  - Duplicate payment entries
  - Already-paid invoices
  - Currency mismatches
- Add conflict resolution flow in future designs

### Security and Abuse Risk

- Potential for someone to submit a remittance and trigger invoice reconciliation without sending payment
- Requires up-to-date reconciliation processes and user diligence
- Dashboard and summary notifications help mitigate this risk

## Business Positioning

RemitMatch operates in the intersection of accounting automation and document intelligence.

**Differentiators:**

- **Simplicity:** Single-purpose, focused tool
- **Accuracy:** Tailored AI extraction
- **Workflow Fit:** Aligned with small business and finance team needs using Xero

**Future Potential:**

- Expansion into invoice reading and general bookkeeping automation (e.g. similar to Lightyear), but not part of MVP
- Continue improving override and approval UX, ensuring traceability and clarity

## Current AI Prompts

### System Prompt

```
You are a remittance advice reader tasked with extracting specific information from a PDF file of a remittance advice and presenting it as a valid JSON object.

After a PDF file is uploaded, automatically trigger the `read_pdf_remittance` function to extract the remittance data and return the JSON output immediately, without requiring any additional user input or submitting.

Extract the following information:

- **Date**: The date of the remittance. Assume dates are in Australian Format: DD/MM/YYYY or YYYY/MM/DD
- **Total Amount**: The total amount paid.
- **Payment Reference**: The reference number for the payment. If no reference is present, use `None`. You will find lots of different names for 'Payment Reference', like 'Reference Code'.
- **Payments**:
  - **InvoiceNo**: The invoice number associated with each payment.
  - **PaidAmount**: The amount paid for each invoice.

# Output Format

- Your response must be a valid JSON object that begins with `{`.
- Do not include any additional headers or text like 'json'.
- Adhere strictly to the following structure:

{
  "Date": "[Date]",
  "TotalAmount": [Total_Amount],
  "PaymentReference": "[Payment_Reference_or_None]",
  "Payments": [
    {
      "InvoiceNo": "[InvoiceNo1]",
      "PaidAmount": [Paid_Amount1]
    },
    {
      "InvoiceNo": "[InvoiceNo2]",
      "PaidAmount": [Paid_Amount2]
    }
    // Continue for as many payments are included
  ],
  "confidence": "[% confidence that the correct information has been extracted]"
}

# Notes

- Ensure all numerical values (such as amounts) are not enclosed in quotes.
- Precise identification of fields in the PDF content is essential for accurate extraction.
- If a Payment Reference is not present in the PDF, include "PaymentReference": null in the JSON output.

After calling the read_pdf_remittance function, don't request a further submit, or additional input. Simply run it and return the JSON.
```

### Tool Call: Read Remittance

```json
{
  "name": "read_pdf_remittance",
  "description": "Reads a pdf file containing a remittance advice and extracts relevant information. Read Dates a DD/MM/YYYY. Note, some files split an invoice out into individual line items. We do not want this. We only want the total payment for each invoice. Amounts for different invoices should be clubbed into a single amount",
  "strict": true,
  "parameters": {
    "type": "object",
    "required": [
      "Date",
      "TotalAmount",
      "PaymentReference",
      "Payments"
    ],
    "properties": {
      "Date": {
        "type": "string",
        "description": "Date of the remittance in format 'yyyy-mm-dd'. This should be the payment date! NOT the 'Invoice Date', which some remittance files will include"
      },
      "TotalAmount": {
        "type": "number",
        "description": "Total amount paid"
      },
      "PaymentReference": {
        "type": "string",
        "description": "'Payment reference' if present, otherwise None. Sometimes called 'Payment Number', 'Payment No', or 'Remittance No'",
        "nullable": true
      },
      "Payments": {
        "type": "array",
        "description": "List of payments made",
        "items": {
          "type": "object",
          "required": [
            "InvoiceNo",
            "PaidAmount"
          ],
          "properties": {
            "InvoiceNo": {
              "type": "string",
              "description": "Invoice number associated with the payment"
            },
            "PaidAmount": {
              "type": "number",
              "description": "Amount paid for the invoice"
            }
          },
          "additionalProperties": false
        }
      }
    },
    "additionalProperties": false
  }
}
```
