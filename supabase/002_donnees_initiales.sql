-- ==========================================================================
-- NexusLab, dashboard interne : données de départ
-- Idempotent : rien n'est créé deux fois, rien de modifié à la main n'est écrasé.
-- ==========================================================================

-- ---------- Membres ----------
-- Les e-mails doivent être ceux des comptes Supabase Auth (sinon accès refusé).
insert into public.membres (nom, role) values
  ('Patrick', 'Leader, direction artistique, communication'),
  ('Mehdi',   'Développement, finances'),
  ('Arno',    'Ventes, contrats')
on conflict (nom) do nothing;

-- ---------- Offres (prix de départ du site nexus-lab.ch, modifiables) ----------
insert into public.offres (nom, description, prix_depart, periode, inclus, ordre) values
  ('Essentiel',
   'Une seule page avec l''essentiel : prestations, horaires, photos, plan d''accès et bouton d''appel. Fiche Google mise à jour.',
   690, 'unique',
   array['Une page, pensée d''abord pour le téléphone','Fiche Google à jour','Contact WhatsApp et appel direct','Mise en ligne comprise'],
   1),
  ('Standard',
   'Un site de trois à cinq pages, contenu modifiable par le client, réservation ou prise de rendez-vous selon le métier.',
   1200, 'unique',
   array['Trois à cinq pages','Contenu que le client modifie lui-même','Rendez-vous ou réservation en ligne','Textes et photos retravaillés avec le client'],
   2),
  ('Suivi',
   'Après la mise en ligne, les changements sont faits par NexusLab : photos, horaires, textes. Sans engagement de durée.',
   30, 'mois',
   array['Modifications sur demande','Nouvelles photos et nouveaux textes','Site maintenu à jour','Sans engagement'],
   3)
on conflict (nom) do nothing;

-- ---------- Paramètres de l'agence (pour les devis et factures) ----------
insert into public.parametres (id, raison_sociale, complement, adresse, npa, localite, email, telephone, site_web, mention_pied)
values (1, 'NexusLab', 'c/o HES-SO Valais-Wallis, Business Team Academy', 'Route de Sous-Géronde 87', '3960', 'Sierre',
        'nexuslab.mpa@gmail.com', '+41 79 737 87 92', 'nexus-lab.ch',
        'NexusLab, projet de Vardena, Team Company de la Business Team Academy, HES-SO Valais-Wallis.')
on conflict (id) do nothing;

-- ---------- Clients ----------
insert into public.clients (nom, secteur, localite, statut, source, notes)
select 'NexusLab', 'Interne', 'Sierre', 'mandat_signe', 'Interne', 'Projets internes de l''agence.'
where not exists (select 1 from public.clients where nom = 'NexusLab');

insert into public.clients (nom, secteur, contact, statut, source, notes)
select 'Lugon Assèchement Sàrl', 'Assèchement, dégâts d''eau', 'François Lugon', 'livre', 'Réseau',
       'Première réalisation. Site qui a remplacé l''abonnement d''annuaire. Poste de commande interne (factures QR, devis, documents).'
where not exists (select 1 from public.clients where nom = 'Lugon Assèchement Sàrl');

insert into public.clients (nom, secteur, localite, statut, source, notes)
select 'Vardena', 'Coopérative (Team Company)', 'Sierre', 'mandat_signe', 'Interne',
       'Coopérative de la classe Business Team Academy, qui porte NexusLab.'
where not exists (select 1 from public.clients where nom = 'Vardena');

-- ---------- Projets (sites) ----------
insert into public.projets (client_id, nom, type, offre_id, statut, version, url_en_ligne, depot_github, domaine,
                            base_supabase, responsable_id, prochaine_etape)
select c.id, 'Site vitrine NexusLab', 'vitrine', null, 'developpement', 'v1', 'https://nexus-lab.ch',
       'nexuslab-ch/Nexus-Site', 'nexus-lab.ch', false,
       (select id from public.membres where nom = 'Mehdi'),
       'Brancher nexus-lab.ch, tester le formulaire, page offres'
from public.clients c
where c.nom = 'NexusLab'
  and not exists (select 1 from public.projets where nom = 'Site vitrine NexusLab');

insert into public.projets (client_id, nom, type, statut, version, url_en_ligne, domaine, base_supabase, prochaine_etape)
select c.id, 'Lugon Assèchement', 'vitrine', 'en_ligne', 'v1', 'https://lugon-assechement.ch',
       'lugon-assechement.ch', true, 'Obtenir l''accord pour la montrer en réalisation, mesurer le chiffre clé'
from public.clients c
where c.nom = 'Lugon Assèchement Sàrl'
  and not exists (select 1 from public.projets where nom = 'Lugon Assèchement');

insert into public.projets (client_id, nom, type, statut, prochaine_etape)
select c.id, 'Site Vardena', 'vitrine', 'brief', 'Rédiger le brief avec Vardena'
from public.clients c
where c.nom = 'Vardena'
  and not exists (select 1 from public.projets where nom = 'Site Vardena');

-- ---------- Journal des versions ----------
insert into public.versions (projet_id, numero, date, notes)
select p.id, 'v1', date '2026-10-07', 'Première version : une page à sections, trois formules, formulaire FormSubmit.'
from public.projets p where p.nom = 'Site vitrine NexusLab'
on conflict (projet_id, numero) do nothing;

insert into public.versions (projet_id, numero, notes)
select p.id, 'v1', 'Site en ligne sur lugon-assechement.ch.'
from public.projets p where p.nom = 'Lugon Assèchement'
on conflict (projet_id, numero) do nothing;
