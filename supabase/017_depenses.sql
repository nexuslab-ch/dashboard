-- ==========================================================================
-- NexusLab, dashboard interne : migration 017 (22.10.2026)
-- Dépenses : chaque achat fait pour NexusLab (papier, impression, logiciel,
-- déplacement...), avec qui a avancé l'argent, le justificatif et le suivi
-- du remboursement, en attendant que la comptabilité de Vardena soit prête.
-- Les justificatifs (photo du ticket, facture) vont dans le stockage
-- « documents », dossier depenses/.
-- Idempotent : peut être relancé sans rien casser.
-- ==========================================================================

create table if not exists public.depenses (
  id                  uuid primary key default gen_random_uuid(),
  date                date not null default current_date,
  libelle             text not null,
  fournisseur         text,
  montant             numeric(10,2) not null check (montant >= 0),
  categorie           text not null default 'autre'
                      check (categorie in ('impression','materiel','logiciel','deplacement','repas','marketing','administratif','autre')),
  projet_id           uuid references public.projets(id) on delete set null,
  client_id           uuid references public.clients(id) on delete set null,
  paye_par            uuid references public.membres(id) on delete set null,
  moyen               text not null default 'avance_membre'
                      check (moyen in ('avance_membre','caisse_nexuslab','vardena')),
  statut              text not null default 'a_rembourser'
                      check (statut in ('a_rembourser','rembourse','sans_objet')),
  rembourse_le        date,
  transmis_vardena    boolean not null default false,
  justificatif_path   text,
  justificatif_nom    text,
  notes               text,
  cree_par            text default (auth.jwt() ->> 'email'),
  cree_le             timestamptz not null default now(),
  modifie_le          timestamptz not null default now()
);
create index if not exists depenses_date_idx on public.depenses (date desc);

drop trigger if exists depenses_modifie_le on public.depenses;
create trigger depenses_modifie_le before update on public.depenses
  for each row execute function public.maj_modifie_le();

alter table public.depenses enable row level security;
revoke all on public.depenses from anon;
grant select, insert, update, delete on public.depenses to authenticated;
drop policy if exists membres_seulement on public.depenses;
create policy membres_seulement on public.depenses for all to authenticated
  using (public.est_membre()) with check (public.est_membre());
