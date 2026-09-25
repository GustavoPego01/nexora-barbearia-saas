-- Etapa 2: estrutura; aplicar como postgres via Supabase migrations.
begin;
create schema if not exists private;
create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;
revoke create on schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema private revoke execute on functions from public, anon, authenticated;

create type public.member_role as enum ('owner','manager','professional','receptionist');
create type public.appointment_status as enum ('scheduled','confirmed','in_progress','completed','cancelled','no_show');
create type public.subscription_status as enum ('trial','active','past_due','cancelled','blocked');
create type public.theme_name as enum ('premium','classic','modern');
create type public.professional_status as enum ('available','vacation','absent','disabled');
create type public.payment_method as enum ('pix','cash','debit','credit','other');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '' check (length(full_name) <= 150),
  phone text check (length(phone) <= 30),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table private.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table public.plans (
  id text primary key check (id in ('starter','pro','premium')),
  name text not null, professional_limit integer check (professional_limit > 0),
  features jsonb not null default '{}' check (jsonb_typeof(features) = 'object')
);
insert into public.plans(id,name,professional_limit) values
  ('starter','Starter',2),('pro','Pro',5),('premium','Premium',null);
create table public.themes (
  id public.theme_name primary key, name text not null
);
insert into public.themes values ('premium','Premium Dark'),('classic','Classic Barber'),('modern','Modern Clean');
create table public.barbershops (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 150),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) <= 100),
  description text not null default '' check (length(description) <= 5000),
  phone text, whatsapp text, instagram text, address text, postal_code text, city text, state text,
  maps_url text check (maps_url is null or maps_url ~ '^https://'),
  logo_path text, cover_path text, welcome_message text not null default '',
  theme public.theme_name not null default 'premium' references public.themes(id),
  primary_color text not null default '#e0b675' check (primary_color ~ '^#[0-9a-fA-F]{6}$'),
  secondary_color text not null default '#141719' check (secondary_color ~ '^#[0-9a-fA-F]{6}$'),
  timezone text not null default 'America/Sao_Paulo',
  is_active boolean not null default true, is_published boolean not null default false,
  onboarding_step smallint not null default 1 check (onboarding_step between 1 and 8),
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  barbershop_id uuid not null unique references public.barbershops(id),
  plan text not null references public.plans(id),
  status public.subscription_status not null default 'trial',
  started_at timestamptz not null default now(), expires_at timestamptz, trial_ends_at timestamptz,
  check (expires_at is null or expires_at > started_at),
  check (status <> 'trial' or trial_ends_at is not null),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.barbershop_members (
  id uuid primary key default gen_random_uuid(),
  barbershop_id uuid not null references public.barbershops(id),
  user_id uuid not null references auth.users(id), role public.member_role not null,
  is_active boolean not null default true,
  unique(barbershop_id,user_id), unique(barbershop_id,id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index members_user_idx on public.barbershop_members(user_id,barbershop_id) where is_active;
create table public.settings (
  barbershop_id uuid primary key references public.barbershops(id),
  cancellation_hours integer not null default 2 check (cancellation_hours between 0 and 168),
  booking_notice_minutes integer not null default 30 check (booking_notice_minutes between 0 and 10080),
  booking_horizon_days integer not null default 30 check (booking_horizon_days between 1 and 365),
  slot_minutes integer not null default 15 check (slot_minutes between 5 and 120),
  commissions_enabled boolean not null default false,
  accepted_payments public.payment_method[] not null default '{pix,cash,debit,credit}',
  reminder_24h boolean not null default true, reminder_2h boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  barbershop_id uuid not null references public.barbershops(id),
  user_id uuid references auth.users(id), name text not null check (length(trim(name)) between 2 and 150),
  phone text not null check (length(phone) between 8 and 30), email text,
  unique(barbershop_id,id), unique(barbershop_id,user_id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
-- Observações privadas separadas: cliente nunca recebe notas internas.
create table public.customer_notes (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  customer_id uuid not null, body text not null check (length(body) between 1 and 10000),
  foreign key(barbershop_id,customer_id) references public.customers(barbershop_id,id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.professionals (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  member_id uuid, name text not null check (length(trim(name)) between 2 and 150),
  phone text, email text, photo_path text, specialties text not null default '',
  status public.professional_status not null default 'available',
  commission_percent numeric(5,2) not null default 0 check (commission_percent between 0 and 100),
  buffer_minutes integer not null default 0 check (buffer_minutes between 0 and 120),
  foreign key(barbershop_id,member_id) references public.barbershop_members(barbershop_id,id),
  unique(barbershop_id,id), unique(barbershop_id,member_id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.services (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  name text not null check (length(trim(name)) between 2 and 150), description text not null default '',
  price_cents integer not null check (price_cents >= 0),
  duration_minutes integer not null check (duration_minutes between 5 and 480),
  image_path text, category text, is_active boolean not null default true,
  unique(barbershop_id,id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.professional_services (
  barbershop_id uuid not null references public.barbershops(id), professional_id uuid not null, service_id uuid not null,
  primary key(barbershop_id,professional_id,service_id),
  foreign key(barbershop_id,professional_id) references public.professionals(barbershop_id,id),
  foreign key(barbershop_id,service_id) references public.services(barbershop_id,id)
);
-- Vários períodos por dia permitem almoço/intervalos sem horários sobrepostos.
create table public.business_hours (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  weekday smallint not null check (weekday between 0 and 6),
  start_minute integer not null check (start_minute between 0 and 1439),
  end_minute integer not null check (end_minute between 1 and 1440), check (end_minute > start_minute),
  exclude using gist (barbershop_id extensions.gist_uuid_ops with =, weekday extensions.gist_int2_ops with =,
    int4range(start_minute,end_minute,'[)') with &&)
);
create table public.professional_schedules (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  professional_id uuid not null, weekday smallint not null check (weekday between 0 and 6),
  start_minute integer not null check (start_minute between 0 and 1439),
  end_minute integer not null check (end_minute between 1 and 1440), check (end_minute > start_minute),
  foreign key(barbershop_id,professional_id) references public.professionals(barbershop_id,id),
  exclude using gist (professional_id extensions.gist_uuid_ops with =, weekday extensions.gist_int2_ops with =,
    int4range(start_minute,end_minute,'[)') with &&)
);
create table public.appointments (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  customer_id uuid not null, professional_id uuid not null, service_id uuid not null,
  starts_at timestamptz not null, ends_at timestamptz not null, occupied_until timestamptz not null,
  status public.appointment_status not null default 'scheduled',
  price_cents integer not null check (price_cents >= 0),
  duration_minutes integer not null check (duration_minutes between 5 and 480),
  commission_percent numeric(5,2) not null default 0 check (commission_percent between 0 and 100),
  source text not null default 'panel' check (source in ('panel','public','whatsapp')),
  check (ends_at > starts_at and occupied_until >= ends_at),
  check (ends_at = starts_at + duration_minutes * interval '1 minute'),
  foreign key(barbershop_id,customer_id) references public.customers(barbershop_id,id),
  foreign key(barbershop_id,professional_id,service_id)
    references public.professional_services(barbershop_id,professional_id,service_id),
  unique(barbershop_id,id),
  exclude using gist (professional_id extensions.gist_uuid_ops with =,
    tstzrange(starts_at,occupied_until,'[)') with &&)
    where (status in ('scheduled','confirmed','in_progress','completed','no_show')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index appointments_tenant_date_idx on public.appointments(barbershop_id,starts_at);
create index appointments_customer_idx on public.appointments(barbershop_id,customer_id,starts_at);
create table public.appointment_notes (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  appointment_id uuid not null, body text not null check (length(body) between 1 and 10000),
  foreign key(barbershop_id,appointment_id) references public.appointments(barbershop_id,id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.blocked_times (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  professional_id uuid, starts_at timestamptz not null, ends_at timestamptz not null,
  reason text not null check (reason in ('lunch','personal','day_off','vacation','maintenance','other')),
  check (ends_at > starts_at),
  foreign key(barbershop_id,professional_id) references public.professionals(barbershop_id,id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index blocked_times_range_idx on public.blocked_times using gist
  (barbershop_id extensions.gist_uuid_ops, tstzrange(starts_at,ends_at,'[)'));
create table public.payments (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  appointment_id uuid not null, amount_cents integer not null check (amount_cents >= 0),
  method public.payment_method not null, paid_at timestamptz not null default now(),
  foreign key(barbershop_id,appointment_id) references public.appointments(barbershop_id,id),
  unique(barbershop_id,appointment_id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index payments_date_idx on public.payments(barbershop_id,paid_at);
create table public.notification_templates (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  event text not null check (event in ('confirmation','reminder','cancellation','reschedule','thanks')),
  body text not null check (length(body) between 1 and 4096), enabled boolean not null default false,
  unique(barbershop_id,event),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  appointment_id uuid not null, event text not null, scheduled_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed','cancelled')),
  attempts integer not null default 0 check (attempts >= 0), deduplication_key text not null,
  foreign key(barbershop_id,appointment_id) references public.appointments(barbershop_id,id),
  unique(barbershop_id,deduplication_key),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index notifications_pending_idx on public.notifications(scheduled_at) where status = 'pending';
create table public.whatsapp_connections (
  barbershop_id uuid primary key references public.barbershops(id), phone text,
  status text not null default 'disconnected' check (status in ('disconnected','configuring','connected','error')),
  phone_number_id text unique, business_account_id text, connected_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
-- Nenhuma coluna de token/segredo nas tabelas da API.
create table public.whatsapp_messages (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  customer_id uuid, appointment_id uuid, provider_message_id text unique,
  direction text not null check (direction in ('inbound','outbound')),
  status text not null check (status in ('received','queued','sent','delivered','read','failed')),
  body text not null check (length(body) <= 10000),
  foreign key(barbershop_id,customer_id) references public.customers(barbershop_id,id),
  foreign key(barbershop_id,appointment_id) references public.appointments(barbershop_id,id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  actor_id uuid, action text not null, entity_table text not null, entity_id text,
  created_at timestamptz not null default now()
);
create index audit_tenant_date_idx on public.audit_logs(barbershop_id,created_at desc);
create table private.support_sessions (
  id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
  admin_id uuid not null references private.platform_admins(user_id),
  reason text not null check (length(trim(reason)) >= 10),
  started_at timestamptz not null default now(), expires_at timestamptz not null,
  ended_at timestamptz, check (expires_at > started_at and expires_at <= started_at + interval '1 hour')
);
-- Índices por tenant inclusive nas tabelas auxiliares e RLS em todas as tabelas próprias.
do $$ declare n text; begin
  foreach n in array array['profiles','plans','themes','barbershops','subscriptions','barbershop_members',
    'settings','customers','customer_notes','professionals','services','professional_services','business_hours',
    'professional_schedules','appointments','appointment_notes','blocked_times','payments','notification_templates',
    'notifications','whatsapp_connections','whatsapp_messages','audit_logs'] loop
    execute format('alter table public.%I enable row level security', n);
    execute format('revoke all on public.%I from public, anon, authenticated', n);
    if exists (select 1 from information_schema.columns where table_schema='public'
      and table_name=n and column_name='barbershop_id') and not exists (
      select 1 from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=i.indkey[0]
      where i.indrelid=format('public.%I',n)::regclass and a.attname='barbershop_id' and i.indpred is null
    ) then
      execute format('create index %I on public.%I(barbershop_id)', n || '_tenant_idx',n);
    end if;
  end loop;
end $$;
alter table private.platform_admins enable row level security;
alter table private.support_sessions enable row level security;
commit;
