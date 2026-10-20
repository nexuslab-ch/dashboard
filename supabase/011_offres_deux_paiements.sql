-- ==========================================================================
-- NexusLab, dashboard interne : offres à deux modes de paiement
-- Chaque formule se paie soit en une fois (création + forfait annuel),
-- soit au mois (mensualité avec engagement). Les options sont à part.
-- Idempotent : peut être relancé sans casser ni dupliquer quoi que ce soit.
-- ==========================================================================

-- ---------- Nouveaux champs ----------
alter table public.offres add column if not exists type text not null default 'formule';
alter table public.offres drop constraint if exists offres_type_check;
alter table public.offres add constraint offres_type_check check (type in ('formule','option'));

alter table public.offres add column if not exists badge text;                         -- ex. « Prix de lancement »
alter table public.offres add column if not exists prix_des boolean not null default false;  -- afficher « dès »
alter table public.offres add column if not exists sur_devis boolean not null default false; -- afficher « sur devis »
alter table public.offres add column if not exists prix_creation numeric(10,2);        -- paiement unique : création
alter table public.offres add column if not exists forfait_annuel numeric(10,2);       -- paiement unique : chaque année
alter table public.offres add column if not exists forfait_annuel_detail text;         -- ce que couvre le forfait annuel
alter table public.offres add column if not exists prix_mensuel numeric(10,2);         -- tout au mois
alter table public.offres add column if not exists engagement_mois integer;            -- durée d'engagement (vide = sans engagement)
alter table public.offres add column if not exists conditions text;                    -- conditions particulières (options)

-- ---------- Nouvelles offres ----------
-- prix_depart et periode restent remplis pour la compatibilité (devis, anciens écrans).
insert into public.offres (nom, type, badge, prix_des, sur_devis, prix_creation, forfait_annuel, prix_mensuel, engagement_mois, prix_depart, periode, description, inclus, conditions, active, ordre) values
  ('Site Essentiel', 'formule', 'Prix de lancement', false, false, 690, 150, 49, 12, 690, 'unique',
   'Une page avec l''essentiel : prestations, horaires, photos, plan d''accès et bouton d''appel.',
   array['Une page, pensée d''abord pour le téléphone','Fiche Google à jour','Contact WhatsApp et appel direct','Mise en ligne comprise'],
   null, true, 1),
  ('Site Standard', 'formule', 'Prix de lancement', false, false, 1290, 190, 89, 12, 1290, 'unique',
   'Un site de trois à cinq pages, contenu modifiable par le client, réservation ou prise de rendez-vous selon le métier.',
   array['Trois à cinq pages','Contenu que le client modifie lui-même','Rendez-vous ou réservation en ligne','Textes et photos retravaillés avec le client'],
   null, true, 2),
  ('Outil de gestion', 'formule', 'Prix de lancement', false, false, 390, 100, 29, 12, 390, 'unique',
   'Un petit outil sur mesure pour gérer le quotidien : réservations, stocks, clients ou planning.',
   array[]::text[], null, true, 3),
  ('ERP / Dashboard', 'formule', 'Prix de lancement', true, true, 1900, 290, 149, 12, 1900, 'unique',
   'Un tableau de bord ou un ERP complet, construit autour des besoins de l''entreprise. Prix établi sur devis.',
   array[]::text[], null, true, 4),
  ('Option Suivi', 'option', 'Prix de lancement', false, false, null, null, 30, null, 30, 'mois',
   'Après la mise en ligne, les changements sont faits par NexusLab : photos, horaires, textes.',
   array['1 h de modifications par mois','Au-delà : CHF 60/h','Sans engagement'],
   'Réservée au paiement unique.', true, 10)
on conflict (nom) do nothing;

-- ---------- Anciennes offres ----------
-- Les sites liés aux anciennes offres sont rattachés à la nouvelle équivalente,
-- pour que le compteur de sites reste juste. Maintien technique n'a pas d'équivalent :
-- le lien est simplement vidé (le site lui-même n'est pas touché).
update public.projets p set offre_id = n.id
  from public.offres a, public.offres n
 where p.offre_id = a.id
   and (a.nom, n.nom) in (('Essentiel','Site Essentiel'), ('Standard','Site Standard'), ('Suivi','Option Suivi'));

delete from public.offres where nom in ('Essentiel', 'Standard', 'Suivi', 'Maintien technique', 'Maintient technique');
