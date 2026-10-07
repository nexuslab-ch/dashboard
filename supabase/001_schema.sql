-- ==========================================================================
-- NexusLab, dashboard interne : schéma de la base (Supabase, Postgres)
-- Idempotent : peut être relancé sans casser ni dupliquer quoi que ce soit.
-- ==========================================================================

-- ---------- Fonction commune : date de modification ----------
create or replace function public.maj_modifie_le()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.modifie_le := now();
  return new;
end;
$$;

-- ---------- membres ----------
create table if not exists public.membres (
  id          uuid primary key default gen_random_uuid(),
  nom         text not null unique,
  role        text,
  email       text unique,
  actif       boolean not null default true,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now()
);

-- ---------- offres ----------
create table if not exists public.offres (
  id           uuid primary key default gen_random_uuid(),
  nom          text not null unique,
  description  text,
  prix_depart  numeric(10,2),
  periode      text not null default 'unique' check (periode in ('unique','mois','an')),
  inclus       text[] not null default '{}',
  active       boolean not null default true,
  ordre        int not null default 0,
  cree_le      timestamptz not null default now(),
  modifie_le   timestamptz not null default now()
);

-- ---------- clients ----------
create table if not exists public.clients (
  id          uuid primary key default gen_random_uuid(),
  nom         text not null,
  secteur     text,
  contact     text,
  email       text,
  telephone   text,
  adresse     text,
  npa         text,
  localite    text,
  statut      text not null default 'prospect'
              check (statut in ('prospect','contacte','rendez_vous','offre_envoyee','mandat_signe','livre','termine','perdu')),
  source      text,
  notes       text,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now()
);

-- ---------- projets (les sites) ----------
create table if not exists public.projets (
  id                  uuid primary key default gen_random_uuid(),
  client_id           uuid references public.clients(id) on delete set null,
  nom                 text not null,
  type                text not null default 'vitrine'
                      check (type in ('vitrine','vitrine_reservation','pack_visibilite','outil','autre')),
  offre_id            uuid references public.offres(id) on delete set null,
  statut              text not null default 'brief'
                      check (statut in ('brief','design','developpement','revue_client','en_ligne','maintenance','termine')),
  version             text,
  url_en_ligne        text,
  depot_github        text,
  projet_netlify      text,
  domaine             text,
  registrar           text,
  base_supabase       boolean not null default false,
  responsable_id      uuid references public.membres(id) on delete set null,
  prochaine_etape     text,
  date_mise_en_ligne  date,
  notes               text,
  cree_le             timestamptz not null default now(),
  modifie_le          timestamptz not null default now()
);

-- ---------- devis et factures ----------
create table if not exists public.devis_factures (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid references public.clients(id) on delete set null,
  projet_id        uuid references public.projets(id) on delete set null,
  type             text not null check (type in ('devis','facture')),
  numero           text not null unique,
  objet            text,
  lignes           jsonb not null default '[]'::jsonb,
  montant_ht       numeric(12,2) not null default 0,
  taux_tva         numeric(5,2) not null default 0,
  montant_tva      numeric(12,2) generated always as (round(montant_ht * taux_tva / 100, 2)) stored,
  montant_ttc      numeric(12,2) generated always as (montant_ht + round(montant_ht * taux_tva / 100, 2)) stored,
  statut           text not null default 'brouillon'
                   check (statut in ('brouillon','envoye','accepte','facture','paye','annule')),
  date_emission    date not null default current_date,
  echeance         date,
  date_paiement    date,
  devis_origine_id uuid references public.devis_factures(id) on delete set null,
  pdf_path         text,
  notes            text,
  cree_le          timestamptz not null default now(),
  modifie_le       timestamptz not null default now()
);

-- ---------- tâches ----------
create table if not exists public.taches (
  id               uuid primary key default gen_random_uuid(),
  titre            text not null,
  description      text,
  projet_id        uuid references public.projets(id) on delete set null,
  responsable_id   uuid references public.membres(id) on delete set null,
  valideur_id      uuid references public.membres(id) on delete set null,
  statut           text not null default 'a_faire'
                   check (statut in ('a_faire','en_cours','a_valider','fait')),
  echeance         date,
  heures_estimees  numeric(6,2),
  heures_reelles   numeric(6,2),
  sprint           text,
  cree_le          timestamptz not null default now(),
  modifie_le       timestamptz not null default now()
);

-- ---------- documents (GED) ----------
create table if not exists public.documents (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid references public.clients(id) on delete set null,
  projet_id     uuid references public.projets(id) on delete set null,
  nom           text not null,
  type          text not null default 'autre'
                check (type in ('contrat','devis','facture','brief','maquette','photo','logo','texte','autre')),
  fichier_path  text not null unique,
  taille        bigint,
  mime          text,
  date          date not null default current_date,
  cree_le       timestamptz not null default now(),
  modifie_le    timestamptz not null default now()
);

-- ---------- versions (journal par site) ----------
create table if not exists public.versions (
  id          uuid primary key default gen_random_uuid(),
  projet_id   uuid not null references public.projets(id) on delete cascade,
  numero      text not null,
  date        date not null default current_date,
  notes       text,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now(),
  unique (projet_id, numero)
);

-- ---------- retours clients ----------
create table if not exists public.retours (
  id          uuid primary key default gen_random_uuid(),
  projet_id   uuid not null references public.projets(id) on delete cascade,
  auteur      text,
  contenu     text not null,
  date        date not null default current_date,
  traite      boolean not null default false,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now()
);

-- ---------- paramètres de l'agence (une seule ligne, pour les PDF) ----------
create table if not exists public.parametres (
  id                    int primary key default 1 check (id = 1),
  raison_sociale        text not null default 'NexusLab',
  complement            text,
  adresse               text,
  npa                   text,
  localite              text,
  pays                  text not null default 'CH',
  email                 text,
  telephone             text,
  site_web              text,
  iban                  text,
  numero_tva            text,
  taux_tva_defaut       numeric(5,2) not null default 0,
  delai_paiement_jours  int not null default 30,
  validite_devis_jours  int not null default 30,
  mention_pied          text,
  cree_le               timestamptz not null default now(),
  modifie_le            timestamptz not null default now()
);

-- ---------- Index utiles ----------
create index if not exists projets_client_idx        on public.projets (client_id);
create index if not exists projets_responsable_idx   on public.projets (responsable_id);
create index if not exists df_client_idx             on public.devis_factures (client_id);
create index if not exists df_projet_idx             on public.devis_factures (projet_id);
create index if not exists taches_projet_idx         on public.taches (projet_id);
create index if not exists taches_responsable_idx    on public.taches (responsable_id);
create index if not exists taches_valideur_idx       on public.taches (valideur_id);
create index if not exists documents_client_idx      on public.documents (client_id);
create index if not exists documents_projet_idx      on public.documents (projet_id);
create index if not exists versions_projet_idx       on public.versions (projet_id);
create index if not exists retours_projet_idx        on public.retours (projet_id);

-- ---------- Déclencheurs : date de modification ----------
do $$
declare t text;
begin
  foreach t in array array['membres','offres','clients','projets','devis_factures','taches','documents','versions','retours','parametres']
  loop
    execute format('drop trigger if exists %I on public.%I', t || '_modifie_le', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.maj_modifie_le()', t || '_modifie_le', t);
  end loop;
end;
$$;

-- ---------- Sécurité : seuls les membres actifs connectés ----------
create or replace function public.est_membre()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.membres m
    where m.actif
      and m.email is not null
      and lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function public.est_membre() from public, anon;
grant execute on function public.est_membre() to authenticated;

-- Numéro suivant : D-2026-001 pour un devis, F-2026-001 pour une facture
create or replace function public.prochain_numero(p_type text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  prefixe text;
  annee   text := to_char(current_date, 'YYYY');
  dernier int;
begin
  if p_type not in ('devis','facture') then
    raise exception 'Type inconnu : %', p_type;
  end if;
  prefixe := case p_type when 'devis' then 'D' else 'F' end || '-' || annee || '-';
  select coalesce(max(substring(numero from length(prefixe) + 1)::int), 0)
    into dernier
    from public.devis_factures
   where numero like prefixe || '%'
     and substring(numero from length(prefixe) + 1) ~ '^[0-9]+$';
  return prefixe || lpad((dernier + 1)::text, 3, '0');
end;
$$;

revoke all on function public.prochain_numero(text) from public, anon;
grant execute on function public.prochain_numero(text) to authenticated;

-- RLS : activée partout, une seule règle par table, réservée aux membres
do $$
declare t text;
begin
  foreach t in array array['membres','offres','clients','projets','devis_factures','taches','documents','versions','retours','parametres']
  loop
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

-- ---------- Stockage des fichiers (GED et PDF) ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('documents', 'documents', false, 52428800)
on conflict (id) do nothing;

drop policy if exists "documents_membres_lecture"      on storage.objects;
drop policy if exists "documents_membres_ajout"        on storage.objects;
drop policy if exists "documents_membres_modification" on storage.objects;
drop policy if exists "documents_membres_suppression"  on storage.objects;

create policy "documents_membres_lecture" on storage.objects
  for select to authenticated
  using (bucket_id = 'documents' and public.est_membre());

create policy "documents_membres_ajout" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'documents' and public.est_membre());

create policy "documents_membres_modification" on storage.objects
  for update to authenticated
  using (bucket_id = 'documents' and public.est_membre())
  with check (bucket_id = 'documents' and public.est_membre());

create policy "documents_membres_suppression" on storage.objects
  for delete to authenticated
  using (bucket_id = 'documents' and public.est_membre());
