# Dashboard NexusLab

Poste de commande interne de NexusLab, à l'identité du site nexus-lab.ch (graphite, blanc cassé, corail).

- **Pilotage** : Ma journée, Agenda (tout ce qui a une date), Objectifs et indicateurs (automatiques ou à la main).
- **Commercial** : Clients et pipeline (glisser-déposer, prochaine action, relances), Offres, Devis et factures (PDF avec QR-facture), Dépenses (qui a avancé l'argent, justificatif, remboursement, export pour la comptabilité de Vardena).
- **Production** : Projets / Sites, Tâches RACI (avec statut Bloqué), Documents (clients et internes).
- **Équipe et BTA** : Équipe (charge, heures, compétences, invités avec accès temporaire), Réunions et registre des décisions (débrief tops / flops), Ressources, Situations apprenantes (objectif 26 validées, couverture des 14 compétences, export des plus marquantes), Wiki (charte, process, guides).
- **Agenda** : export .ics vers Google Agenda, Apple Calendrier ou Outlook.
- **Tâches** : commentaires, et création d’une situation apprenante depuis une tâche.
- Partout : recherche Cmd+K et bouton « Créer ».

## Ce qu'il y a dans ce dépôt

- `index.html` : toute l'application (HTML, CSS, JavaScript), sans build.
- `fonts/` : Manrope, hébergée avec le site.
- `supabase/001_schema.sql` : tables, règles RLS, stockage. Idempotent, peut être relancé.
- `supabase/002_donnees_initiales.sql` : membres, offres, clients et sites de départ. Idempotent.
- `supabase/003_documents_internes.sql`, `supabase/004_pilotage_equipe.sql`, `supabase/005_suivi_prospects.sql`, `supabase/006_bta_wiki_commentaires.sql`, `supabase/007_etat_comptes.sql`, `supabase/008_agenda_abonnement.sql` : évolutions, à exécuter dans l'ordre. Idempotentes. Tant que la 006 n'est pas lancée, le dashboard fonctionne et affiche « module à activer » sur les nouvelles pages.
- `_headers` : en-têtes de sécurité Netlify (page non indexée, CSP).

## Fonctionnement

- Base de données, comptes et fichiers : Supabase (région Zurich). Le front ne contient que l'URL du projet et la clé publique `anon`. La clé `service_role` ne doit jamais apparaître ici.
- Accès : seuls les comptes dont l'e-mail figure dans la table `membres` (actif) lisent et écrivent. Inscriptions publiques désactivées ; les comptes sont créés par invitation depuis Supabase.
- Hébergement : Netlify, relié à ce dépôt, déploiement automatique à chaque envoi sur `main`.

## Ajouter un membre

1. Supabase, Authentication, Users : « Invite user » avec son e-mail.
2. Dashboard, Équipe : « Membre », même e-mail.
3. La personne clique le lien reçu et choisit son mot de passe.

## Ajouter un invité (Rocket Week)

1. Même démarche qu'un membre, puis renseigner « Accès jusqu’au » dans sa fiche.
2. Après cette date, la base refuse automatiquement son accès (fonction `est_membre`).

## Ajouter quelqu'un (membre ou invité)

Supabase n'envoie que 2 e-mails par heure avec son service intégré : les invitations et les « mot de passe oublié » échouent vite (« Trop de tentatives »). Méthode fiable, sans e-mail :

1. Supabase, Authentication, Users, Add user, Create new user : e-mail de la personne, mot de passe provisoire, cocher « Auto Confirm User ».
2. Dashboard, Équipe, Membre : même e-mail, à la lettre près. Pour un invité, remplir « Accès jusqu'au » : l'accès s'arrête tout seul après cette date.
3. Donner le mot de passe provisoire de vive voix ou par message ; la personne le change dans Réglages.

La carte « Connexions à vérifier » (page Équipe) signale un compte sans fiche ou une fiche sans compte.

## Synchronisation avec Google Agenda, Apple Calendrier, Outlook

Bouton « Synchroniser mon agenda » (page Agenda) : chaque membre reçoit un lien personnel, lu par son agenda et mis à jour automatiquement (tâches R ou A, réunions, relances, mises en ligne, objectifs). Le lien passe par la fonction Edge dont le code est dans `supabase/fonction-agenda.ts`, à déployer une fois dans Supabase (Edge Functions, nom `agenda`, **vérification JWT désactivée**, car les agendas n'envoient pas d'en-tête ; la sécurité repose sur le jeton de 64 caractères). Migration requise : `008_agenda_abonnement.sql`.
