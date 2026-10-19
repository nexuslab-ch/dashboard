-- ==========================================================================
-- NexusLab, dashboard interne : entretiens découverte (Rocket Week)
-- Chaque entretien est rattaché à une fiche client : les coordonnées
-- saisies pendant l'entretien vont directement dans le répertoire.
-- Idempotent : peut être relancé sans casser ni dupliquer quoi que ce soit.
-- ==========================================================================

create table if not exists public.entretiens (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.clients(id) on delete cascade,
  membre_id   uuid references public.membres(id) on delete set null,
  date        date not null default current_date,
  interet     text check (interet in ('pas_interesse','curieux','demo','devis')),
  reponses    jsonb not null default '{}'::jsonb,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now()
);
create index if not exists entretiens_client_idx on public.entretiens (client_id, date desc);

drop trigger if exists entretiens_modifie_le on public.entretiens;
create trigger entretiens_modifie_le before update on public.entretiens
  for each row execute function public.maj_modifie_le();

alter table public.entretiens enable row level security;
revoke all on public.entretiens from anon;
grant select, insert, update, delete on public.entretiens to authenticated;
drop policy if exists membres_seulement on public.entretiens;
create policy membres_seulement on public.entretiens for all to authenticated
  using (public.est_membre()) with check (public.est_membre());
