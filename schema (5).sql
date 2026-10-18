-- KAZIAR : base de données Supabase (à coller dans SQL Editor puis Run)

create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  nom text,
  role text not null default 'employe' check (role in ('admin','employe'))
);

create table if not exists public.records (
  collection text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (collection, id)
);
create index if not exists records_collection_idx on public.records (collection);

alter table public.profiles enable row level security;
alter table public.records  enable row level security;

create or replace function public.is_admin() returns boolean
language sql security definer set search_path = public stable as
$$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin') $$;

create or replace function public.is_member() returns boolean
language sql security definer set search_path = public stable as
$$ select exists(select 1 from public.profiles where id = auth.uid()) $$;

-- profil créé automatiquement à la création d'un utilisateur (rôle employé par défaut)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  insert into public.profiles(id, nom) values (new.id, new.raw_user_meta_data->>'nom') on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- profiles
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select using (id = auth.uid() or public.is_admin());
drop policy if exists profiles_admin on public.profiles;
create policy profiles_admin on public.profiles for all using (public.is_admin()) with check (public.is_admin());

-- records : paiements = admin seulement ; settings/employes = écriture admin ; suppression = admin
drop policy if exists rec_read on public.records;
create policy rec_read on public.records for select
  using (public.is_member() and (collection not in ('paiements','prets','cheques') or public.is_admin()));

drop policy if exists rec_insert on public.records;
create policy rec_insert on public.records for insert
  with check (public.is_member() and (collection not in ('paiements','prets','cheques','settings','employes') or public.is_admin()));

drop policy if exists rec_update on public.records;
create policy rec_update on public.records for update
  using (public.is_member() and (collection not in ('paiements','prets','cheques','settings','employes') or public.is_admin()))
  with check (public.is_member() and (collection not in ('paiements','prets','cheques','settings','employes') or public.is_admin()));

drop policy if exists rec_delete on public.records;
create policy rec_delete on public.records for delete using (public.is_admin());

-- temps réel
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='records') then
    alter publication supabase_realtime add table public.records;
  end if;
end $$;

-- profils pour les utilisateurs déjà créés avant ce script
insert into public.profiles(id) select id from auth.users on conflict do nothing;

-- informations de la société (modifiables ensuite dans l'onglet Société)
insert into public.records(collection, id, data) values
 ('settings','soc', jsonb_build_object(
   'nom','KAZIAR CONSTRUCTION',
   'adr','8, Bd Qods, RDC, Hay Moulay Abdellah, Casablanca, Maroc',
   'tel','06 60 26 18 68','wa','212660261868','mail','kaziar.office@gmail.com',
   'ice','','rc','','rib','')) on conflict (collection,id) do nothing;

-- APRÈS avoir créé votre utilisateur (Authentication > Users), remplacez l'email puis exécutez :
-- update public.profiles set role = 'admin' where id = (select id from auth.users where email = 'VOTRE_EMAIL');
