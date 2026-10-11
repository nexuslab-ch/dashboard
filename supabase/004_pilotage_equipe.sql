-- ==========================================================================
-- NexusLab, dashboard interne : pilotage de l'équipe (version 2)
-- Objectifs et indicateurs, réunions et décisions, ressources, compétences,
-- relances clients, statut « bloqué » pour les tâches.
-- Idempotent : peut être relancé sans casser ni dupliquer quoi que ce soit.
-- ==========================================================================

-- ---------- Clients : prochaine action et date de relance (pipeline) ----------
alter table public.clients add column if not exists prochaine_action text;
alter table public.clients add column if not exists date_relance date;
create index if not exists clients_relance_idx on public.clients (date_relance);

-- ---------- Objectifs (ex. Rocket Week) ----------
create table if not exists public.objectifs (
  id          uuid primary key default gen_random_uuid(),
  titre       text not null unique,
  description text,
  debut       date,
  fin         date,
  actif       boolean not null default true,
  ordre       int not null default 0,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now()
);

-- Indicateurs d'un objectif : valeur saisie à la main ou calculée par le dashboard
create table if not exists public.indicateurs (
  id           uuid primary key default gen_random_uuid(),
  objectif_id  uuid not null references public.objectifs(id) on delete cascade,
  libelle      text not null,
  cible        numeric(12,2) not null default 0,
  valeur       numeric(12,2) not null default 0,
  source       text not null default 'manuel'
               check (source in ('manuel','clients_contactes','rendez_vous','devis_envoyes','mandats_signes','ca_facture','ca_encaisse','taches_faites')),
  unite        text,
  ordre        int not null default 0,
  cree_le      timestamptz not null default now(),
  modifie_le   timestamptz not null default now(),
  unique (objectif_id, libelle)
);

-- ---------- Réunions (séances, débriefs, points client) ----------
create table if not exists public.reunions (
  id             uuid primary key default gen_random_uuid(),
  titre          text not null,
  type           text not null default 'seance' check (type in ('seance','debrief','client','atelier','autre')),
  date           date not null default current_date,
  heure          text,
  lieu           text,
  participants   uuid[] not null default '{}',
  client_id      uuid references public.clients(id) on delete set null,
  projet_id      uuid references public.projets(id) on delete set null,
  ordre_du_jour  text,
  notes          text,
  tops           text,
  flops          text,
  cree_le        timestamptz not null default now(),
  modifie_le     timestamptz not null default now()
);

-- Registre des décisions
create table if not exists public.decisions (
  id          uuid primary key default gen_random_uuid(),
  reunion_id  uuid references public.reunions(id) on delete set null,
  date        date not null default current_date,
  texte       text not null,
  statut      text not null default 'adoptee' check (statut in ('adoptee','refusee','reportee','a_discuter')),
  vote        text,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now()
);

-- ---------- Ressources et liens utiles ----------
create table if not exists public.ressources (
  id           uuid primary key default gen_random_uuid(),
  titre        text not null,
  url          text,
  categorie    text not null default 'outil' check (categorie in ('outil','bta','vardena','modele','guide','client','autre')),
  description  text,
  epingle      boolean not null default false,
  cree_le      timestamptz not null default now(),
  modifie_le   timestamptz not null default now(),
  unique (titre)
);

-- ---------- Compétences par membre ----------
create table if not exists public.competences (
  id          uuid primary key default gen_random_uuid(),
  membre_id   uuid not null references public.membres(id) on delete cascade,
  nom         text not null,
  niveau      int not null default 1 check (niveau between 1 and 5),
  objectif    int check (objectif between 1 and 5),
  notes       text,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now(),
  unique (membre_id, nom)
);

-- ---------- Tâches : statut « bloqué » et lien vers une réunion ----------
alter table public.taches add column if not exists reunion_id uuid references public.reunions(id) on delete set null;
alter table public.taches drop constraint if exists taches_statut_check;
alter table public.taches add constraint taches_statut_check
  check (statut in ('a_faire','en_cours','bloque','a_valider','fait'));

-- ---------- Index ----------
create index if not exists indicateurs_objectif_idx on public.indicateurs (objectif_id);
create index if not exists reunions_date_idx        on public.reunions (date);
create index if not exists decisions_reunion_idx    on public.decisions (reunion_id);
create index if not exists competences_membre_idx   on public.competences (membre_id);
create index if not exists taches_reunion_idx       on public.taches (reunion_id);

-- ---------- Déclencheurs, RLS : même règle que les autres tables ----------
do $$
declare t text;
begin
  foreach t in array array['objectifs','indicateurs','reunions','decisions','ressources','competences']
  loop
    execute format('drop trigger if exists %I on public.%I', t || '_modifie_le', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.maj_modifie_le()', t || '_modifie_le', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', 'membres_seulement', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (public.est_membre()) with check (public.est_membre())',
      'membres_seulement', t);
  end loop;
end;
$$;

-- ---------- Données de départ ----------
-- Objectif Rocket Week (plan v2 du 7.10.2026)
insert into public.objectifs (titre, description, debut, fin, ordre)
values ('Rocket Week', 'Rencontrer 15 PME de Sierre, Sion et la Riviera, dont 10 sur rendez-vous pris avant la semaine, pour obtenir 5 retours écrits, 3 demandes de devis et viser 1 mandat signé via le SAEI.',
        date '2026-10-12', date '2026-10-22', 1)
on conflict (titre) do nothing;

insert into public.indicateurs (objectif_id, libelle, cible, source, ordre)
select o.id, v.libelle, v.cible, v.source, v.ordre
from public.objectifs o
cross join (values
  ('PME contactées',        30, 'clients_contactes', 1),
  ('Rendez-vous pris',      10, 'rendez_vous',       2),
  ('PME rencontrées',       15, 'manuel',            3),
  ('Retours écrits',         5, 'manuel',            4),
  ('Demandes de devis',      3, 'devis_envoyes',     5),
  ('Mandats signés',         1, 'mandats_signes',    6)
) as v(libelle, cible, source, ordre)
where o.titre = 'Rocket Week'
on conflict (objectif_id, libelle) do nothing;

-- Ressources utiles
insert into public.ressources (titre, url, categorie, description, epingle) values
  ('Site nexus-lab.ch',            'https://nexus-lab.ch',                                       'outil',   'Le site vitrine de NexusLab.', true),
  ('Plan Rocket Week v2 (Notion)', 'https://app.notion.com/p/3f248b505997811dad23f9c13b088589',  'bta',     'Objectif SMART, planning, indicateurs et risques.', true),
  ('Vardena, pilotage du CA',      'https://app.notion.com/p/3ea48b505997817ba413f4539ddeacdc',  'vardena', 'Organisation du CA, réunions, registre des décisions, finances.', true),
  ('GitHub nexuslab-ch',           'https://github.com/nexuslab-ch',                             'outil',   'Le code de tous les sites clients.', false),
  ('Netlify NexusLab',             'https://app.netlify.com/teams/nexuslab-mpa/projects',        'outil',   'Hébergement et déploiement des sites.', false),
  ('Supabase NexusLab',            'https://supabase.com/dashboard/project/tyboklsnivmtqbbrgiuy', 'outil',  'Base de données et comptes du dashboard.', false)
on conflict (titre) do nothing;
