-- ==========================================================================
-- NexusLab, dashboard interne : migration 014 (20.10.2026)
-- Sécurité : seuls les associés peuvent créer, modifier ou supprimer une fiche membre.
-- Avant : tout membre connecté, y compris un invité temporaire, pouvait modifier la table
-- membres (par exemple effacer sa propre date de fin d'accès, ou ajouter quelqu'un).
-- Associé = membre actif SANS date de fin d'accès (acces_jusquau vide).
-- Idempotent : peut être relancé sans rien casser.
-- ==========================================================================

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

-- Remplace la règle unique « membres_seulement » de la table membres par deux règles :
-- lecture pour tous les membres, écriture pour les associés.
drop policy if exists membres_seulement on public.membres;
drop policy if exists membres_lecture on public.membres;
drop policy if exists membres_ajout_associes on public.membres;
drop policy if exists membres_modif_associes on public.membres;
drop policy if exists membres_suppr_associes on public.membres;

create policy membres_lecture on public.membres
  for select to authenticated using (public.est_membre());

create policy membres_ajout_associes on public.membres
  for insert to authenticated with check (public.est_associe());

create policy membres_modif_associes on public.membres
  for update to authenticated using (public.est_associe()) with check (public.est_associe());

create policy membres_suppr_associes on public.membres
  for delete to authenticated using (public.est_associe());
