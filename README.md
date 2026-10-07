# Dashboard NexusLab

Poste de commande interne de NexusLab : clients, sites, offres, devis et factures (PDF avec QR-facture), tâches RACI, équipe, documents.

## Ce qu'il y a dans ce dépôt

- `index.html` : toute l'application (HTML, CSS, JavaScript), sans build.
- `fonts/` : Manrope, hébergée avec le site.
- `supabase/001_schema.sql` : tables, règles RLS, stockage. Idempotent, peut être relancé.
- `supabase/002_donnees_initiales.sql` : membres, offres, clients et sites de départ. Idempotent.
- `_headers` : en-têtes de sécurité Netlify (page non indexée, CSP).

## Fonctionnement

- Base de données, comptes et fichiers : Supabase (région Zurich). Le front ne contient que l'URL du projet et la clé publique `anon`. La clé `service_role` ne doit jamais apparaître ici.
- Accès : seuls les comptes dont l'e-mail figure dans la table `membres` (actif) lisent et écrivent. Inscriptions publiques désactivées ; les comptes sont créés par invitation depuis Supabase.
- Hébergement : Netlify, relié à ce dépôt, déploiement automatique à chaque envoi sur `main`.

## Ajouter un membre

1. Supabase, Authentication, Users : « Invite user » avec son e-mail.
2. Dashboard, Équipe : « Membre », même e-mail.
3. La personne clique le lien reçu et choisit son mot de passe.
