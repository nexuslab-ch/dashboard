-- ==========================================================================
-- NexusLab, dashboard interne : migration 016 (21.10.2026)
-- Fichiers des « Documents confidentiels » (playbooks, prompts, templates complets).
-- Stockage séparé « confidentiel », privé, lisible et modifiable par les associés seulement.
-- Le stockage « documents » (fiches clients) reste ouvert à tous les membres.
-- Idempotent : peut être relancé sans rien casser.
-- ==========================================================================

insert into storage.buckets (id, name, public, file_size_limit)
values ('confidentiel', 'confidentiel', false, 52428800)
on conflict (id) do update set public = false;

drop policy if exists "confidentiel_associes_lecture"      on storage.objects;
drop policy if exists "confidentiel_associes_ajout"        on storage.objects;
drop policy if exists "confidentiel_associes_modification" on storage.objects;
drop policy if exists "confidentiel_associes_suppression"  on storage.objects;

create policy "confidentiel_associes_lecture" on storage.objects
  for select to authenticated using (bucket_id = 'confidentiel' and public.est_associe());
create policy "confidentiel_associes_ajout" on storage.objects
  for insert to authenticated with check (bucket_id = 'confidentiel' and public.est_associe());
create policy "confidentiel_associes_modification" on storage.objects
  for update to authenticated using (bucket_id = 'confidentiel' and public.est_associe())
  with check (bucket_id = 'confidentiel' and public.est_associe());
create policy "confidentiel_associes_suppression" on storage.objects
  for delete to authenticated using (bucket_id = 'confidentiel' and public.est_associe());

-- Un fichier rattaché à une fiche de service
create table if not exists public.recettes_fichiers (
  id          uuid primary key default gen_random_uuid(),
  recette_id  uuid not null references public.recettes(id) on delete cascade,
  nom         text not null,
  role        text not null default 'autre' check (role in ('prompt','playbook','template','exemple','autre')),
  chemin      text not null unique,
  taille      bigint,
  mime        text,
  ajoute_par  text default (auth.jwt() ->> 'email'),
  ajoute_le   timestamptz not null default now()
);
create index if not exists recettes_fichiers_idx on public.recettes_fichiers (recette_id, ajoute_le);

alter table public.recettes_fichiers enable row level security;
revoke all on public.recettes_fichiers from anon;
grant select, insert, update, delete on public.recettes_fichiers to authenticated;
drop policy if exists associes_seulement on public.recettes_fichiers;
create policy associes_seulement on public.recettes_fichiers for all to authenticated
  using (public.est_associe()) with check (public.est_associe());
