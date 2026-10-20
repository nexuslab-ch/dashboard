-- ==========================================================================
-- NexusLab, dashboard interne : mails reçus sur contact@nexus-lab.ch
-- Resend reçoit le mail (MX du domaine), appelle la fonction Edge
-- « recevoir-mail », qui le range ici et le transfère vers le Gmail commun.
-- Idempotent : peut être relancé sans rien casser.
-- ==========================================================================

create table if not exists public.mails_recus (
  id              uuid primary key default gen_random_uuid(),
  resend_id       text unique,
  client_id       uuid references public.clients(id) on delete set null,
  expediteur      text not null,
  expediteur_nom  text,
  destinataires   text,
  sujet           text,
  texte           text,
  pieces          jsonb not null default '[]'::jsonb,
  transfere       boolean not null default false,
  lu              boolean not null default false,
  recu_le         timestamptz not null default now()
);
create index if not exists mails_recus_client_idx on public.mails_recus (client_id, recu_le desc);
create index if not exists mails_recus_recu_idx on public.mails_recus (recu_le desc);

alter table public.mails_recus enable row level security;
revoke all on public.mails_recus from anon;
grant select, update, delete on public.mails_recus to authenticated;
drop policy if exists membres_seulement on public.mails_recus;
create policy membres_seulement on public.mails_recus for all to authenticated
  using (public.est_membre()) with check (public.est_membre());
-- Pas d'ajout depuis le navigateur : seule la fonction Edge (clé serveur) range les mails reçus.
