-- Create users table
CREATE TABLE IF NOT EXISTS public.users (
    id SERIAL PRIMARY KEY,
    created_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    email TEXT UNIQUE NOT NULL,
    first_name TEXT,
    last_name TEXT,
    gender TEXT,
    profile_image_url TEXT,
    user_id TEXT UNIQUE NOT NULL,
    subscription TEXT
);

-- Create payments table
CREATE TABLE IF NOT EXISTS public.payments (
    id SERIAL PRIMARY KEY,
    created_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
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

-- Create subscriptions table
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id SERIAL PRIMARY KEY,
    created_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
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

-- Create subscriptions_plans table
CREATE TABLE IF NOT EXISTS public.subscriptions_plans (
    id SERIAL PRIMARY KEY,
    created_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    plan_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    amount TEXT NOT NULL,
    currency TEXT NOT NULL,
    interval TEXT NOT NULL
);

-- Create invoices table
CREATE TABLE IF NOT EXISTS public.invoices (
    id SERIAL PRIMARY KEY,
    created_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    invoice_id TEXT NOT NULL,
    subscription_id TEXT NOT NULL,
    amount_paid TEXT NOT NULL,
    amount_due TEXT,
    currency TEXT NOT NULL,
    status TEXT NOT NULL,
    email TEXT NOT NULL,
    user_id TEXT
);

-- Enable Row Level Security (RLS) for all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

-- Create RLS policies (basic examples - adjust based on your needs)
-- Users can only see their own data
CREATE POLICY "Users can view own data" ON public.users
    FOR SELECT USING (auth.uid()::text = user_id);

CREATE POLICY "Users can update own data" ON public.users
    FOR UPDATE USING (auth.uid()::text = user_id);

-- Similar policies for other tables
CREATE POLICY "Users can view own payments" ON public.payments
    FOR SELECT USING (auth.uid()::text = user_id);

CREATE POLICY "Users can view own subscriptions" ON public.subscriptions
    FOR SELECT USING (auth.uid()::text = user_id);

CREATE POLICY "Users can view own invoices" ON public.invoices
    FOR SELECT USING (auth.uid()::text = user_id);

-- Admin policies for subscriptions_plans (assuming this is public data)
CREATE POLICY "Anyone can view subscription plans" ON public.subscriptions_plans
    FOR SELECT USING (true);