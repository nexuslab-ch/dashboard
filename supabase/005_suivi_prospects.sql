-- ==========================================================================
-- NexusLab, dashboard interne : suivi des prospects
-- Attribution d'un client à un membre, journal des contacts partagé,
-- accès temporaires (date de fin d'accès sur un membre).
-- Idempotent : peut être relancé sans casser ni dupliquer quoi que ce soit.
-- ==========================================================================

-- ---------- Clients : membre qui suit le prospect ----------
alter table public.clients add column if not exists responsable_id uuid references public.membres(id) on delete set null;
create index if not exists clients_responsable_idx on public.clients (responsable_id);

-- ---------- Journal des contacts (appels, messages, visites...) ----------
create table if not exists public.contacts_clients (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.clients(id) on delete cascade,
  membre_id   uuid references public.membres(id) on delete set null,
  date        date not null default current_date,
  canal       text not null default 'appel'
              check (canal in ('appel','whatsapp','email','sms','visite','rendez_vous','linkedin','autre')),
  resultat    text not null default 'sans_reponse'
              check (resultat in ('sans_reponse','a_rappeler','interesse','rdv_pris','devis_demande','pas_interesse','autre')),
  notes       text,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now()
);
create index if not exists contacts_clients_client_idx on public.contacts_clients (client_id, date desc);

drop trigger if exists contacts_clients_modifie_le on public.contacts_clients;
create trigger contacts_clients_modifie_le before update on public.contacts_clients
  for each row execute function public.maj_modifie_le();

alter table public.contacts_clients enable row level security;
revoke all on public.contacts_clients from anon;
grant select, insert, update, delete on public.contacts_clients to authenticated;
drop policy if exists membres_seulement on public.contacts_clients;
create policy membres_seulement on public.contacts_clients for all to authenticated
  using (public.est_membre()) with check (public.est_membre());

-- ---------- Accès temporaires ----------
-- Un membre avec une date de fin d'accès perd l'accès le lendemain de cette date.
alter table public.membres add column if not exists acces_jusquau date;

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
      and (m.acces_jusquau is null or m.acces_jusquau >= (now() at time zone 'Europe/Zurich')::date)
  );
$$;

revoke all on function public.est_membre() from public, anon;
grant execute on function public.est_membre() to authenticated;

-- Tassilo : accès temporaire jusqu'au 23.10.2026 (Rocket Week)
insert into public.membres (nom, role, email, actif, acces_jusquau)
values ('Tassilo', 'Vente (accès temporaire)', 'poteltassilo3@gmail.com', true, date '2026-10-23')
on conflict (nom) do update set email = excluded.email, acces_jusquau = excluded.acces_jusquau, actif = true;
