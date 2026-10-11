-- ==========================================================================
-- NexusLab, dashboard interne : documents internes (BTA, Vardena, administratif)
-- Idempotent : peut être relancé sans casser ni dupliquer quoi que ce soit.
-- ==========================================================================

-- Un document interne n'appartient à aucun client ni site
alter table public.documents add column if not exists interne boolean not null default false;

-- Nouveaux types : présentation, cours, administratif, procès-verbal
alter table public.documents drop constraint if exists documents_type_check;
alter table public.documents add constraint documents_type_check
  check (type in ('contrat','devis','facture','brief','maquette','photo','logo','texte',
                  'presentation','cours','administratif','proces_verbal','autre'));

create index if not exists documents_interne_idx on public.documents (interne);
