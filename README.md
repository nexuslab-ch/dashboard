# Dashboard NexusLab

Poste de commande interne de NexusLab, à l'identité du site nexus-lab.ch (graphite, blanc cassé, corail).

- **Pilotage** : Ma journée, Agenda (tout ce qui a une date), Objectifs et indicateurs (automatiques ou à la main).
- **Commercial** : Clients et pipeline (glisser-déposer, prochaine action, relances), Offres, Devis et factures (PDF avec QR-facture).
- **Production** : Projets / Sites, Tâches RACI (avec statut Bloqué), Documents (clients et internes).
- **Équipe et BTA** : Équipe (charge, heures, compétences), Réunions et registre des décisions (débrief tops / flops), Ressources.
- Partout : recherche Cmd+K et bouton « Créer ».

## Ce qu'il y a dans ce dépôt

- `index.html` : toute l'application (HTML, CSS, JavaScript), sans build.
- `fonts/` : Manrope, hébergée avec le site.
- `supabase/001_schema.sql` : tables, règles RLS, stockage. Idempotent, peut être relancé.
- `supabase/002_donnees_initiales.sql` : membres, offres, clients et sites de départ. Idempotent.
- `supabase/003_documents_internes.sql`, `supabase/004_pilotage_equipe.sql` : évolutions, à exécuter dans l'ordre. Idempotentes.
- `_headers` : en-têtes de sécurité Netlify (page non indexée, CSP).

## Fonctionnement

- Base de données, comptes et fichiers : Supabase (région Zurich). Le front ne contient que l'URL du projet et la clé publique `anon`. La clé `service_role` ne doit jamais apparaître ici.
- Accès : seuls les comptes dont l'e-mail figure dans la table `membres` (actif) lisent et écrivent. Inscriptions publiques désactivées ; les comptes sont créés par invitation depuis Supabase.
- Hébergement : Netlify, relié à ce dépôt, déploiement automatique à chaque envoi sur `main`.

## Ajouter un membre

1. Supabase, Authentication, Users : « Invite user » avec son e-mail.
2. Dashboard, Équipe : « Membre », même e-mail.
3. La personne clique le lien reçu et choisit son mot de passe.
