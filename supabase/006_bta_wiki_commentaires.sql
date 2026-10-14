-- ==========================================================================
-- NexusLab, dashboard interne : version 3
-- Situations apprenantes (BTA), wiki de l'équipe, commentaires sur les tâches.
-- Idempotent : peut être relancé sans casser ni dupliquer quoi que ce soit.
-- ==========================================================================

-- Accès temporaires : déjà créés par 005_suivi_prospects.sql (colonne acces_jusquau et est_membre()).
-- À lancer APRÈS 005_suivi_prospects.sql.

-- ---------- Situations apprenantes (Business Team Academy) ----------
create table if not exists public.situations (
  id             uuid primary key default gen_random_uuid(),
  date           date not null default current_date,
  titre          text not null,
  ce_que_jai_fait text,
  apprentissage  text,
  membre_id      uuid references public.membres(id) on delete set null,
  projet_id      uuid references public.projets(id) on delete set null,
  tache_id       uuid references public.taches(id) on delete set null,
  competences    int[] not null default '{}',
  heures         numeric(6,2),
  preuve         text,
  validee        boolean not null default false,
  marquante      boolean not null default false,
  cree_le        timestamptz not null default now(),
  modifie_le     timestamptz not null default now()
);
create index if not exists situations_membre_idx on public.situations (membre_id);
create index if not exists situations_date_idx   on public.situations (date);

-- ---------- Wiki : pages libres (charte, process, guides) ----------
create table if not exists public.pages (
  id          uuid primary key default gen_random_uuid(),
  titre       text not null unique,
  categorie   text not null default 'equipe' check (categorie in ('equipe','process','guide','client','bta','autre')),
  contenu     text,
  epingle     boolean not null default false,
  modifie_par uuid references public.membres(id) on delete set null,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now()
);

-- ---------- Commentaires (sur les tâches pour l'instant) ----------
create table if not exists public.commentaires (
  id          uuid primary key default gen_random_uuid(),
  tache_id    uuid not null references public.taches(id) on delete cascade,
  membre_id   uuid references public.membres(id) on delete set null,
  texte       text not null,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now()
);
create index if not exists commentaires_tache_idx on public.commentaires (tache_id);

-- ---------- Déclencheurs, RLS : même règle que les autres tables ----------
do $$
declare t text;
begin
  foreach t in array array['situations','pages','commentaires']
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

-- ---------- Page de départ du wiki ----------
insert into public.pages (titre, categorie, contenu, epingle) values
  ('Comment on utilise le dashboard', 'process',
'# Comment on utilise le dashboard

Le dashboard remplace petit à petit notre Notion.

## Où mettre quoi
- **Tâches** : tout ce qui doit être fait, avec un responsable (R), un valideur (A) et une échéance.
- **Réunions et décisions** : chaque réunion, ses décisions et ses actions.
- **Situations apprenantes** : ce que chacun a appris dans un projet, avec la compétence, les heures et la preuve. Objectif BTA : 26 validées par semestre.
- **Wiki** : la charte, nos process et nos guides.

## Règles
- Une action sans responsable ni échéance n''existe pas.
- La préparation d''une réunion se fait au plus tard la veille.
- Les invités (Rocket Week) ont un accès qui s''arrête tout seul à la date prévue.', true)
on conflict (titre) do nothing;
