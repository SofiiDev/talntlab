-- ═══════════════════════════════════════════════════
-- TalentLab — Supabase Setup
-- Ejecutar en: Supabase → SQL Editor → New query
-- ═══════════════════════════════════════════════════

-- 1. TABLA DE PERFILES
create table if not exists profiles (
  id uuid references auth.users on delete cascade primary key,
  email text unique not null,
  name text not null,
  titulo text,
  resumen text,
  tel text,
  linkedin text,
  ubicacion text,
  skills jsonb default '[]',
  idiomas jsonb default '[]',
  exp jsonb default '[]',
  edu jsonb default '[]',
  certs jsonb default '[]',
  score integer default 0,
  foto_url text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 2. TABLA DE AVISOS
create table if not exists jobs (
  id text primary key default 'TL-' || extract(epoch from now())::bigint,
  titulo text not null,
  area text,
  empresa text default 'TalentLab',
  ubicacion text,
  modalidad text,
  salario text,
  descripcion text,
  requisitos text,
  url text,
  status text default 'activo',
  postulations integer default 0,
  created_at timestamptz default now()
);

-- 3. TABLA DE POSTULACIONES
create table if not exists applications (
  id text primary key default 'APP-' || extract(epoch from now())::bigint,
  candidate_id uuid references profiles(id) on delete cascade,
  candidate_email text,
  candidate_name text,
  job_id text,
  job_title text,
  job_src text,
  job_url text,
  status text default 'Pendiente',
  created_at timestamptz default now()
);

-- 4. ROW LEVEL SECURITY
alter table profiles enable row level security;
alter table jobs enable row level security;
alter table applications enable row level security;

-- Profiles: cada usuario ve y edita solo el suyo
create policy "Perfil propio" on profiles
  for all using (auth.uid() = id);

-- Jobs: acceso total (datos públicos, sin info sensible)
-- Si ya existen políticas anteriores, ejecutar primero:
-- drop policy if exists "Jobs publicos" on jobs;
-- drop policy if exists "Jobs insert auth" on jobs;
-- drop policy if exists "Jobs update auth" on jobs;
create policy "Jobs all operations" on jobs
  for all using (true) with check (true);

-- Applications: candidato ve las suyas
create policy "Apps propias" on applications
  for all using (auth.uid() = candidate_id);

-- 5. TRIGGER para updated_at
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger profiles_updated_at
  before update on profiles
  for each row execute function update_updated_at();

-- 6. Vista para admin (lee todos los perfiles)
-- Usada desde el panel admin con service_role key
create or replace view admin_profiles as
  select * from profiles;

-- 7. STORAGE — Bucket para fotos de perfil
-- Ejecutar en: Supabase → SQL Editor
-- También podés crear el bucket desde: Storage → New bucket → avatars → Public ON

insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true)
  on conflict (id) do update set public = true;

-- Permitir lectura pública de avatars
create policy "Avatars públicos" on storage.objects
  for select using (bucket_id = 'avatars');

-- Permitir a usuarios autenticados subir su propia foto
create policy "Subir avatar propio" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = 'avatars'
  );

-- Permitir a usuarios autenticados actualizar su propia foto
create policy "Actualizar avatar propio" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = split_part(storage.filename(name), '.', 1)
  );

-- MIGRACIÓN: agregar columna url si no existe (ejecutar si la tabla ya fue creada sin ella)
alter table jobs add column if not exists url text;
-- MIGRACIÓN: agregar columna logo_url a jobs (ejecutar si la tabla ya existe)
alter table jobs add column if not exists logo_url text;

-- ═══════════════════════════════════════════════════
-- PANEL DE RECLUTADOR — Ejecutar para habilitar
-- ═══════════════════════════════════════════════════

-- 8. TABLA DE RECLUTADORES
create table if not exists recruiters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null unique,
  empresa text not null,
  contacto text,
  email text not null,
  plan text default 'free',
  created_at timestamptz default now()
);
alter table recruiters enable row level security;
create policy "Recruiter self access" on recruiters
  for all using (auth.uid() = user_id);

-- 9. COLUMNAS DE RECLUTADOR EN JOBS
alter table jobs add column if not exists recruiter_id uuid references auth.users;
alter table jobs add column if not exists recruiter_email text;

-- 10. PROFILES: reclutadores pueden leer todos los perfiles
-- (adicional a la política existente "Perfil propio")
create policy "Recruiters view all profiles" on profiles
  for select using (
    auth.uid() in (select user_id from recruiters)
  );

-- 11. APPLICATIONS: reclutadores pueden ver y actualizar postulaciones a sus avisos
create policy "Recruiters view own job apps" on applications
  for select using (
    exists (
      select 1 from jobs j
      where j.id = applications.job_id
        and j.recruiter_id = auth.uid()
    )
  );

create policy "Recruiters update own job apps" on applications
  for update using (
    exists (
      select 1 from jobs j
      where j.id = applications.job_id
        and j.recruiter_id = auth.uid()
    )
  );

-- 12. LOGO DE EMPRESA PARA RECLUTADORES
alter table recruiters add column if not exists logo_url text;

-- Bucket para logos de empresa
insert into storage.buckets (id, name, public)
  values ('logos', 'logos', true)
  on conflict (id) do update set public = true;

-- Lectura pública de logos
create policy "Logos públicos" on storage.objects
  for select using (bucket_id = 'logos');

-- Reclutadores pueden subir su propio logo
create policy "Subir logo propio" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'logos'
    and auth.uid()::text = split_part(storage.filename(name), '.', 1)
  );

-- Reclutadores pueden actualizar su propio logo
create policy "Actualizar logo propio" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'logos'
    and auth.uid()::text = split_part(storage.filename(name), '.', 1)
  );

-- ═══════════════════════════════════════════════════
-- AGENDA DE ENTREVISTAS Y PRUEBAS TÉCNICAS
-- ═══════════════════════════════════════════════════

-- 13. TABLA DE ENTREVISTAS
create table if not exists interviews (
  id              uuid primary key default gen_random_uuid(),
  recruiter_id    uuid references auth.users on delete cascade not null,
  candidate_email text not null,
  candidate_name  text,
  job_id          text references jobs(id) on delete set null,
  job_title       text,
  type            text not null default 'Entrevista',
  scheduled_at    timestamptz not null,
  location        text,
  notes           text,
  status          text not null default 'Programada',
  created_at      timestamptz default now()
);
alter table interviews enable row level security;
create policy "Recruiter own interviews" on interviews
  for all using (auth.uid() = recruiter_id);

-- 14. TABLA DE NOTAS DE CANDIDATOS
create table if not exists candidate_notes (
  id              uuid primary key default gen_random_uuid(),
  recruiter_id    uuid references auth.users on delete cascade not null,
  candidate_email text not null,
  note            text not null,
  created_at      timestamptz default now()
);
alter table candidate_notes enable row level security;
create policy "Recruiter own notes" on candidate_notes
  for all using (auth.uid() = recruiter_id);

-- ═══════════════════════════════════════════════════════
-- NUEVAS TABLAS v2 — Evaluaciones de entrevistas
-- Ejecutar con el botón SQL Editor en Supabase
-- ═══════════════════════════════════════════════════════

-- Evaluaciones / tests asignados a candidatos en proceso
create table if not exists interview_evaluations (
  id               uuid primary key default gen_random_uuid(),
  recruiter_id     uuid references auth.users on delete cascade not null,
  candidate_email  text not null,
  job_id           text,
  titulo           text not null,
  descripcion      text,
  tipo             text default 'Técnica', -- 'Técnica', 'Psicológica', 'Idiomas', 'Otro'
  fecha_limite     date,
  resultado        text,
  puntaje          integer,
  status           text default 'Pendiente', -- 'Pendiente', 'Completada', 'Cancelada'
  created_at       timestamptz default now()
);
alter table interview_evaluations enable row level security;
create policy "Recruiter own evaluations" on interview_evaluations
  for all using (auth.uid() = recruiter_id);

-- ¡Listo! Ahora configurá las variables en index.html y admin.html
