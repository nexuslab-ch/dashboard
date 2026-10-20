-- ==========================================================================
-- NexusLab, dashboard interne : mails envoyés depuis le dashboard (Resend)
-- Les mails partent de la fonction Edge « envoyer-mail » ; cette table en garde
-- l'historique. Idempotent : peut être relancé sans rien casser.
-- ==========================================================================

create table if not exists public.mails_envoyes (
  id             uuid primary key default gen_random_uuid(),
  client_id      uuid references public.clients(id) on delete set null,
  membre_id      uuid references public.membres(id) on delete set null,
  destinataire   text not null,
  copie          text,
  sujet          text not null,
  corps          text not null,
  devis_id       uuid references public.devis_factures(id) on delete set null,
  piece_jointe   text,
  modele         text,
  statut         text not null default 'envoye' check (statut in ('envoye','erreur')),
  erreur         text,
  fournisseur_id text,
  cree_le        timestamptz not null default now()
);
create index if not exists mails_envoyes_client_idx on public.mails_envoyes (client_id, cree_le desc);

alter table public.mails_envoyes enable row level security;
revoke all on public.mails_envoyes from anon;
grant select on public.mails_envoyes to authenticated;
drop policy if exists membres_lecture on public.mails_envoyes;
create policy membres_lecture on public.mails_envoyes for select to authenticated using (public.est_membre());
-- Pas d'écriture depuis le navigateur : seule la fonction Edge (clé serveur) ajoute des lignes.

-- Téléphone de chaque membre, pour la signature des mails
alter table public.membres add column if not exists telephone text;
