-- Fresh project only. This migration is not applied to the prototype database.
-- PostGIS must be installed in extensions. Review and execute with RLS tests
-- in a disposable Supabase project before deploying any live user data.
begin;
create schema if not exists extensions;
create extension if not exists postgis with schema extensions;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  locale text not null default 'en' check (locale in ('en','bn')),
  adult_attested boolean not null check (adult_attested),
  created_at timestamptz not null default now()
);

create table public.report_submissions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  category text not null check (category in ('obstruction','lighting','theft','harassment','accident','other')),
  description text not null check (char_length(btrim(description)) between 10 and 700),
  location extensions.geography(Point,4326) not null,
  observed_at timestamptz not null,
  created_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending','reviewed','rejected')),
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  unique(owner_id,client_request_id),
  check (observed_at <= created_at + interval '5 minutes'),
  check (observed_at >= created_at - interval '72 hours')
);
create index report_submissions_owner_time on public.report_submissions(owner_id,created_at desc);
create index report_submissions_pending on public.report_submissions(created_at) where status='pending';
create index report_submissions_location on public.report_submissions using gist(location);

-- Public-facing evidence is separate from exact private submissions. Only the
-- moderation service writes sanitized, coarse road events; no reporter identity
-- or free-text submission is exposed in this table.
create table public.road_events (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid unique references public.report_submissions(id) on delete cascade,
  category text not null check (category in ('obstruction','lighting','theft','harassment','accident','other')),
  road_segment_id text not null,
  centroid extensions.geography(Point,4326) not null,
  public_summary text not null check (char_length(public_summary) between 1 and 200),
  observed_at timestamptz not null,
  expires_at timestamptz not null check (expires_at > observed_at),
  published_at timestamptz not null default now()
);
create index road_events_time on public.road_events(expires_at);
create index road_events_location on public.road_events using gist(centroid);

create table public.risk_snapshots (
  id uuid primary key default gen_random_uuid(),
  graph_version text not null,
  scoring_version text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null check (expires_at > created_at)
);
create table public.edge_risk (
  snapshot_id uuid not null references public.risk_snapshots(id) on delete cascade,
  edge_id text not null,
  risk_signal double precision check (risk_signal between 0 and 1),
  uncertainty double precision not null check (uncertainty between 0 and 1),
  confidence double precision not null check (confidence between 0 and 1),
  independent_event_count integer not null check (independent_event_count >= 0),
  primary key(snapshot_id,edge_id),
  -- An unobserved edge is explicitly unknown, never zero risk by default.
  check ((independent_event_count=0 and risk_signal is null and confidence=0 and uncertainty=1)
    or (independent_event_count>0 and risk_signal is not null))
);

-- Future SOS integration: a transaction creates the incident and durable jobs.
-- No client write grants or notification sender are enabled in this slice.
create table public.incidents (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  status text not null default 'active' check (status in ('active','ended','cancelled')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  unique(owner_id,client_request_id),
  check ((status='active' and ended_at is null) or (status<>'active' and ended_at is not null))
);
create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null references public.incidents(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key text not null unique,
  channel text not null check (channel in ('push','sms')),
  status text not null default 'queued' check (status in ('queued','sending','provider_accepted','failed','cancelled')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index notification_outbox_ready on public.notification_outbox(available_at) where status='queued';

alter table public.profiles enable row level security;
alter table public.report_submissions enable row level security;
alter table public.road_events enable row level security;
alter table public.risk_snapshots enable row level security;
alter table public.edge_risk enable row level security;
alter table public.incidents enable row level security;
alter table public.notification_outbox enable row level security;

-- Remove Supabase's broad default table grants, then grant only selected paths.
revoke all on public.profiles,public.report_submissions,public.road_events,
  public.risk_snapshots,public.edge_risk,public.incidents,public.notification_outbox from anon,authenticated;
grant select,insert on public.profiles to authenticated;
grant update(display_name,locale) on public.profiles to authenticated;
grant select,delete on public.report_submissions to authenticated;
-- Never grant submission_id: it links a sanitized event to a private submission.
grant select(id,category,road_segment_id,centroid,public_summary,observed_at,expires_at,published_at)
  on public.road_events to authenticated;
grant select on public.risk_snapshots,public.edge_risk,public.incidents to authenticated;
grant all on public.profiles,public.report_submissions,public.road_events,
  public.risk_snapshots,public.edge_risk,public.incidents,public.notification_outbox to service_role;

create policy profiles_select_own on public.profiles for select to authenticated using (id=(select auth.uid()));
create policy profiles_insert_own on public.profiles for insert to authenticated with check (id=(select auth.uid()));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id=(select auth.uid())) with check (id=(select auth.uid()));
create policy submissions_select_own on public.report_submissions for select to authenticated
  using (owner_id=(select auth.uid()));
create policy submissions_delete_own on public.report_submissions for delete to authenticated
  using (owner_id=(select auth.uid()));
create policy events_visible on public.road_events for select to authenticated using (expires_at>now());
create policy snapshots_visible on public.risk_snapshots for select to authenticated using (expires_at>now());
create policy edge_risk_visible on public.edge_risk for select to authenticated using (
  exists(select 1 from public.risk_snapshots s where s.id=snapshot_id and s.expires_at>now())
);
create policy incidents_select_own on public.incidents for select to authenticated using (owner_id=(select auth.uid()));
-- notification_outbox has no client policy. RLS denies all client operations.
commit;
