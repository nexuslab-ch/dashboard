-- ==========================================================================
-- NexusLab, dashboard interne : abonnement à l'agenda
-- Chaque membre a un lien personnel (jeton) que Google Agenda, Apple Calendrier
-- ou Outlook lisent via la fonction Edge « agenda » (code : supabase/fonction-agenda.ts).
-- Un membre ne voit et ne gère que son propre jeton. Idempotent.
-- ==========================================================================
create or replace function public.mon_membre_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id from public.membres m
  where m.actif and m.email is not null
    and lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  limit 1;
$$;
revoke all on function public.mon_membre_id() from public, anon;
grant execute on function public.mon_membre_id() to authenticated;

create table if not exists public.jetons_agenda (
  membre_id  uuid primary key references public.membres(id) on delete cascade,
  jeton      text not null unique default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  cree_le    timestamptz not null default now()
);

alter table public.jetons_agenda enable row level security;
revoke all on public.jetons_agenda from anon;
grant select, insert, delete on public.jetons_agenda to authenticated;
drop policy if exists mon_jeton on public.jetons_agenda;
create policy mon_jeton on public.jetons_agenda for all to authenticated
  using (public.est_membre() and membre_id = public.mon_membre_id())
  with check (public.est_membre() and membre_id = public.mon_membre_id());
