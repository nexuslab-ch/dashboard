-- ==========================================================================
-- NexusLab, dashboard interne : signature des mails (modèle de Mehdi)
-- Nom complet et titre affichés dans la signature, par exemple
-- « Patrick Lugon » et « Co-fondateur » (devient « Co-fondateur · NexusLab »).
-- Idempotent : peut être relancé sans rien casser.
-- ==========================================================================

alter table public.membres add column if not exists nom_complet text;
alter table public.membres add column if not exists titre text;
