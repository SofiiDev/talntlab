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

-- Jobs: lectura pública
create policy "Jobs publicos" on jobs
  for select using (true);

-- Jobs: escritura para usuarios autenticados (admin usa service_role que bypasea RLS,
-- pero estas políticas cubren configuraciones donde sea necesario)
create policy "Jobs insert auth" on jobs
  for insert to authenticated with check (true);

create policy "Jobs update auth" on jobs
  for update to authenticated using (true);

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

-- ¡Listo! Ahora configurá las variables en index.html y admin.html
