-- ==========================================================================
-- NexusLab, dashboard interne : migration 018 (22.10.2026)
-- Projets / Sites : plusieurs personnes sur un même mandat.
-- « responsable_id » reste la personne qui mène le mandat (R) ;
-- « equipe » liste tous les membres qui y travaillent, responsable compris.
-- Idempotent : peut être relancé sans rien casser.
-- ==========================================================================

alter table public.projets add column if not exists equipe uuid[] not null default '{}';

-- Le responsable actuel de chaque site fait partie de son équipe
update public.projets
set equipe = array_append(equipe, responsable_id)
where responsable_id is not null and not (responsable_id = any(equipe));

create index if not exists projets_equipe_idx on public.projets using gin (equipe);
