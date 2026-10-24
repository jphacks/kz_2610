-- Test harness only: Auth's verified uid context and Storage's metadata schema.
-- Never deploy this file to Supabase. The actual migration is executed unchanged.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create table auth.users(id uuid primary key, raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
create schema storage;
create table storage.buckets(id text primary key, name text, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id), name text not null, unique(bucket_id,name));
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1];
$$;
grant usage on schema public, storage to anon, authenticated, service_role;
grant select,insert,update,delete on storage.objects to anon, authenticated;
grant all on storage.buckets, storage.objects to service_role;
