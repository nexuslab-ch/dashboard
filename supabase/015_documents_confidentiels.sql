-- ==========================================================================
-- NexusLab, dashboard interne : migration 015 (21.10.2026)
-- « Documents confidentiels » : la recette de chaque service NexusLab
-- (prompt, playbook, template, checklist, prix interne, exemple, apprentissages).
-- Réservé aux associés (membre actif SANS date de fin d'accès, voir est_associe()).
-- Un invité comme Tassilo ne voit rien : la protection est dans la base, pas dans la page.
-- Chaque modification archive automatiquement la version précédente.
-- Idempotent : peut être relancé sans rien casser.
-- ==========================================================================

-- Même définition que la migration 014 (recréée ici au cas où la 014 n'a pas été lancée)
create or replace function public.est_associe()
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
      and m.acces_jusquau is null
      and lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.est_associe() from public, anon;
grant execute on function public.est_associe() to authenticated;

-- ---------- Une fiche par service ----------
create table if not exists public.recettes (
  id                 uuid primary key default gen_random_uuid(),
  numero             integer generated always as identity unique,
  service            text not null,
  categorie          text not null default 'outil' check (categorie in ('site','dashboard','outil','contenu','autre')),
  version            text not null default '1.0',
  statut             text not null default 'brouillon' check (statut in ('brouillon','valide','obsolete')),
  date_version       date not null default current_date,
  responsable_id     uuid references public.membres(id) on delete set null,
  objectif           text,
  prompt             text,
  playbook           text,
  template           text,
  checklist          text,
  prix_interne       text,
  exemple            text,
  exemple_client_id  uuid references public.clients(id) on delete set null,
  apprentissages     text,
  sources            text,
  cree_le            timestamptz not null default now(),
  modifie_le         timestamptz not null default now()
);

drop trigger if exists recettes_modifie_le on public.recettes;
create trigger recettes_modifie_le before update on public.recettes
  for each row execute function public.maj_modifie_le();

-- ---------- Historique : chaque version remplacée est gardée ----------
create table if not exists public.recettes_historique (
  id           uuid primary key default gen_random_uuid(),
  recette_id   uuid not null references public.recettes(id) on delete cascade,
  version      text,
  contenu      jsonb not null,
  archive_le   timestamptz not null default now(),
  archive_par  text
);
create index if not exists recettes_historique_idx on public.recettes_historique (recette_id, archive_le desc);

create or replace function public.archiver_recette()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.recettes_historique (recette_id, version, contenu, archive_par)
  values (old.id, old.version, to_jsonb(old), auth.jwt() ->> 'email');
  return new;
end;
$$;
drop trigger if exists recettes_archive on public.recettes;
create trigger recettes_archive before update on public.recettes
  for each row execute function public.archiver_recette();

-- ---------- Accès : associés seulement ----------
alter table public.recettes enable row level security;
alter table public.recettes_historique enable row level security;
revoke all on public.recettes from anon;
revoke all on public.recettes_historique from anon;
grant select, insert, update, delete on public.recettes to authenticated;
grant select on public.recettes_historique to authenticated;

drop policy if exists associes_seulement on public.recettes;
create policy associes_seulement on public.recettes for all to authenticated
  using (public.est_associe()) with check (public.est_associe());
drop policy if exists associes_lecture on public.recettes_historique;
create policy associes_lecture on public.recettes_historique for select to authenticated
  using (public.est_associe());

-- ---------- Première fiche : l'outil de stock Textilirium (modèle) ----------
insert into public.recettes (service, categorie, version, statut, responsable_id, objectif, prompt, playbook, template, checklist, prix_interne, exemple, exemple_client_id, apprentissages, sources)
select
  'Outil de stock (vente au mètre et à la pièce)', 'outil', '0.1', 'brouillon',
  (select id from public.membres where lower(email) = 'p.lugon@icloud.com' limit 1),
  $t$Supprimer la fiche papier des ventes dans un petit commerce qui suit son stock dans un Excel. Sur une tablette à côté de la caisse : chercher le code, taper les mètres ou les pièces vendus, valider, et le stock baisse tout seul. Un article à zéro passe en « fini ». Un bouton exporte le stock en Excel pour la comptable. Pas dans la première version : lien avec la caisse, comptes par vendeur, statistiques, étiquettes QR.$t$,
  $t$Prompt de départ : voir le doc du projet Claude « claude/prompt-chat-mvp-textilirium.md » (version du 20.10.2026). À remplacer ici par la version générique, sans les données du client, une fois le MVP validé.

Structure du prompt :
1. Qui on est (NexusLab, chef de projet non développeur) et le client.
2. Avant de commencer : lire les documents du client (analyse des besoins, résumé du rendez-vous, copie de l'inventaire).
3. Le besoin en résumé.
4. Mission en 3 étapes : analyser le fichier, vérifier ce qui existe déjà, puis seulement après accord construire le MVP.
5. Calendrier et règles (données privées, pas de logiciel tiers installé, vérifier les prix).$t$,
  $t$1. Entretien découverte (guide du dashboard) : comment le stock est tenu, qui le met à jour, ce qui fait perdre du temps.
2. Rendez-vous avec la personne qui gère le stock : récupérer une COPIE du fichier, jamais l'original.
3. Analyse du fichier : onglets, colonnes, formules, codes en double, cellules vides, unités (mètre ou pièce).
4. Vérifier l'existant (ERP, caisses avec stock) et prouver la valeur ajoutée de notre outil.
5. Plan du MVP (écrans, données, outils) validé en équipe, puis maquette sur tablette avec les vrais articles.
6. Prix fixé avec Mehdi avant la démo. Démo gratuite, mise en place payante, offre écrite remise le jour de la démo.
7. Une semaine d'essai en gardant la fiche papier à côté.
8. Mise en service, export pour la comptable, puis suivi.$t$,
  $t$À compléter après la maquette (prévue pour le 30.10.2026) : lien vers le dépôt GitHub du template, structure de la feuille de données, écrans de la tablette.$t$,
  $t$Copie du fichier reçue, original jamais touché
Données du client rangées seulement sur le PC et dans sa fiche du dashboard
Codes uniques vérifiés, unités (mètre ou pièce) notées
Comparaison avec l'existant faite et prix vérifiés sur les sites officiels
Plan du MVP validé par l'équipe
Maquette testée sur tablette avec les vrais articles
Prix fixé avec Mehdi avant la démo
Offre écrite prête le jour de la démo
Semaine d'essai avec la fiche papier à côté
Export Excel testé avec la comptable$t$,
  $t$À fixer avec Mehdi avant la démo. Démo gratuite, mise en place payante. Offre de référence NexusLab : abonnement mensuel tout compris (environ 60 CHF par mois) ou achat unique, à confirmer.$t$,
  $t$Textilirium, magasin de tissus : rendez-vous du 20.10.2026, stock tenu dans un Excel par fournisseur, ventes notées sur papier puis retapées.$t$,
  (select id from public.clients where nom ilike '%textilirium%' limit 1),
  $t$Vérifier ce qui existe avant de construire (un ERP à environ 30 CHF par mois a été cité par Simon Zürcher, de Sympl.). NexusLab n'installe pas de logiciels tiers : la comparaison sert à prouver notre valeur. La cliente a peur pour son fichier : travailler sur une copie et le dire tout de suite rassure.$t$,
  $t$Prompt du chat MVP | Projet Claude HES-SO | claude/prompt-chat-mvp-textilirium.md
Analyse des besoins (v2) et résumé du rendez-vous | Dashboard, fiche client Textilirium |
Transcription du rendez-vous | PC de Patrick | HES > Transcriptions
Copie de l'inventaire | PC de Patrick | HES > NexusLab > Clients > Textilirium$t$
where not exists (select 1 from public.recettes where service = 'Outil de stock (vente au mètre et à la pièce)');
