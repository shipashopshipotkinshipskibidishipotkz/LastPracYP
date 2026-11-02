-- Minimal Supabase Auth contract for an isolated CI PostgreSQL instance.
create schema auth;
create schema extensions;
create role anon;
create role authenticated;
create role service_role bypassrls;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
create table auth.users (
 instance_id uuid, id uuid primary key, aud text, role text, email text unique, encrypted_password text,
 email_confirmed_at timestamptz, raw_app_meta_data jsonb, raw_user_meta_data jsonb, created_at timestamptz, updated_at timestamptz,
 confirmation_token text, email_change text, email_change_token_new text, recovery_token text
);
create table auth.identities(id uuid primary key, provider_id text, user_id uuid references auth.users(id) on delete cascade,
 identity_data jsonb, provider text, created_at timestamptz, updated_at timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id) on delete cascade);
