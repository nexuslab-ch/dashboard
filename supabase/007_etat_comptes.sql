-- ==========================================================================
-- NexusLab, dashboard interne : état des comptes de connexion
-- Liste les comptes de connexion sans fiche membre, et les fiches sans compte,
-- pour la carte « Connexions à vérifier » de la page Équipe.
-- Réservé aux membres. Idempotent.
-- ==========================================================================
create or replace function public.etat_comptes()
returns table (email text, a_compte boolean, a_fiche boolean, fiche text, derniere_connexion timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(lower(u.email), lower(m.email)) as email,
         u.id is not null as a_compte,
         m.id is not null as a_fiche,
         m.nom as fiche,
         u.last_sign_in_at as derniere_connexion
  from auth.users u
  full outer join public.membres m on lower(m.email) = lower(u.email)
  where public.est_membre()
    and (u.id is null or m.id is null)
    and (m.id is null or m.actif);
$$;
revoke all on function public.etat_comptes() from public, anon;
grant execute on function public.etat_comptes() to authenticated;
