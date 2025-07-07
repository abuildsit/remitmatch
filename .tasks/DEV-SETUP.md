# Development Setup Guide

## Auto-Login Test User Setup

### 1. Create Test User in Clerk Dashboard

1. Go to your Clerk dashboard
2. Navigate to "Users" section
3. Click "Create User"
4. Create a user with:
   - Email: `test@remitmatch.dev`
   - Password: `TestPassword123!`
   - Name: `Test User`

### 2. Environment Variables

The following environment variables are already configured in `.env.local`:

```env
# Development Mode
NODE_ENV=development
DEV_MODE=true

# Test User for Development
DEV_TEST_USER_EMAIL=test@remitmatch.dev
DEV_TEST_USER_PASSWORD=TestPassword123!
```

### 3. How Auto-Login Works

- **Development Mode Only**: Auto-login only works when `NODE_ENV=development` and `DEV_MODE=true`
- **Real Authentication**: Uses actual Clerk authentication - no bypassing of auth flows
- **RLS Compatible**: All RLS policies work normally since it's a real authenticated user
- **Visual Indicator**: Shows a yellow dev mode indicator in bottom-right corner

### 4. Setting Up Test Data

After the test user is created and auto-logged in, you'll need to:

1. **Create Test Organization**: 
   - The test user needs to belong to an organization
   - Create an organization through the UI or database

2. **Add Organization Membership**:
   ```sql
   INSERT INTO public.organisation_members (user_id, organisation_id, role)
   VALUES ('test-user-id', 'test-org-id', 'owner');
   ```

3. **Test Different Roles**:
   - You can change the test user's role to test different permissions
   - Available roles: `owner`, `admin`, `user`, `auditor`

### 5. Switching Between Test Users

To test different user roles or scenarios:

1. **Method 1**: Change role in database
   ```sql
   UPDATE public.organisation_members 
   SET role = 'admin' 
   WHERE user_id = 'test-user-id';
   ```

2. **Method 2**: Create additional test users
   - Create more test users in Clerk dashboard
   - Update `DEV_TEST_USER_EMAIL` in `.env.local`

### 6. Troubleshooting

- **Auto-login not working**: Check browser console for error messages
- **User not found**: Ensure test user is created in Clerk dashboard
- **Access denied**: Verify user has organization membership with appropriate role
- **RLS errors**: Check that test user ID matches the one in database

### 7. Development Workflow

1. Start development servers: `npm run dev`
2. Auto-login happens automatically on page load
3. Test RLS policies with different user roles
4. Monitor auth status in browser console (dev mode logging enabled)

### 8. Security Notes

- Auto-login is **disabled in production** (only works in development)
- Test credentials are in `.env.local` (not committed to git)
- All authentication flows remain secure and unchanged
- RLS policies provide full data protection even in development