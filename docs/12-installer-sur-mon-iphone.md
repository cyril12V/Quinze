# Installer Quinze sur ton iPhone (usage perso, sans Mac)

Ce chemin installe l'app **pour toi seul**, sans App Store, sans TestFlight et sans attendre de validation d'Apple. Le **blocage des apps fonctionne** : il utilise l'autorisation « Family Controls » de développement, active d'office. La demande « Family Controls (Distribution) » ne sert qu'à distribuer l'app à d'autres personnes.

Compte environ une heure la première fois, dont 20 à 30 minutes d'attente pendant la compilation. Ensuite, chaque nouvelle version se fait en deux clics.

## Ce qu'il te faut

| Quoi | Prix | Pourquoi |
|---|---|---|
| Compte **Apple Developer** | 99 $/an | Signer l'app et utiliser Temps d'écran. Un compte gratuit ne donne pas accès à Family Controls |
| Compte **GitHub** | gratuit | Compiler l'app sur un Mac dans le cloud |
| Compte **Diawi** | gratuit | Obtenir un lien d'installation à ouvrir sur l'iPhone |
| Un iPhone sous **iOS 17 ou plus** | — | — |

Supabase et la clé Anthropic sont **facultatifs**. Sans eux, l'app fonctionne en **mode local** :
- pas de compte à créer ;
- tes progrès restent sur l'iPhone ;
- le professeur répond à partir des explications intégrées à l'app ;
- pour les réponses libres que l'IA aurait vérifiées, l'app te montre la réponse attendue et te demande si la tienne était juste.

Tu pourras brancher Supabase plus tard (voir la fin du guide) sans perdre tes progrès.

## 1. Mettre le projet sur GitHub

1. Crée un compte sur github.com, puis un **dépôt privé** vide nommé `quinze` (bouton « New repository », coche « Private », ne coche rien d'autre).
2. Envoie le code **sans le dézipper**, même depuis un iPhone :
   - Sur la page du dépôt : « Add file > Upload files » (ou le lien « uploading an existing file » d'un dépôt vide), choisis `quinze.zip`, puis « Commit changes ».
   - Puis « Add file > Create new file », nom `.github/workflows/iphone.yml`, colle le contenu du fichier `.github/workflows/iphone.yml` du projet, puis « Commit changes ».
   - L'onglet **Actions** déballe le zip tout seul (une minute). Pour chaque mise à jour, envoie simplement le nouveau zip de la même façon.
   - GitHub interdit au robot de modifier les workflows : seul `iphone.yml` est indispensable, les autres (`engine.yml`, `ios.yml`, `testflight.yml`) s'ajoutent à la main si tu en veux.
   - Dépôt **privé** : environ 200 minutes de Mac gratuites par mois, soit 7 à 8 compilations. Dépôt **public** : illimité, mais le code est visible (aucun secret n'y est).

## 2. Préparer le compte Apple Developer

1. Inscris-toi sur developer.apple.com/programs. La validation prend de quelques heures à deux jours.
2. **Team ID** : developer.apple.com > Account > Membership details. C'est un code de 10 caractères, par exemple `AB12CD34EF`.
3. **Clé d'API** : appstoreconnect.apple.com > Users and Access > Integrations > App Store Connect API > Team Keys, puis « + ».
   - Nom : `GitHub`. Accès : **Admin**.
   - Télécharge le fichier `AuthKey_XXXXXXXXXX.p8`. Apple ne le propose **qu'une seule fois** : garde-le précieusement.
   - Note le **Key ID** (10 caractères) et l'**Issuer ID** (affiché au-dessus de la liste, sous forme d'UUID).

4. **Une seule fois, sur developer.apple.com > Certificates, Identifiers & Profiles > Identifiers.** L'API d'Apple ne sait ni activer Family Controls ni rattacher un App Group, il faut donc le faire à la main :
   - Crée l'App Group `group.<préfixe>.quinze` (menu en haut à droite : App Groups, puis « + »).
   - Crée les 4 identifiants d'app (App IDs > App) : `<préfixe>.quinze`, `.quinze.monitor`, `.quinze.shieldconfig`, `.quinze.shieldaction`.
   - Sur chacun, coche **Family Controls (Development)** et **App Groups**, clique sur « Configure », choisis le groupe, puis « Save ».

   La compilation crée ensuite toute seule ce que l'API permet : Sign in with Apple sur l'app, le certificat et les profils de développement.

## 3. Trouver l'identifiant (UDID) de ton iPhone

L'app sera signée uniquement pour ton iPhone, il faut donc son UDID (40 caractères hexadécimaux, ou 25 avec un tiret sur les iPhone récents). Deux façons :
- **Sur un PC Windows** : branche l'iPhone, ouvre l'app « Appareils Apple » ou iTunes. Sur la fiche de l'iPhone, clique sur le numéro de série : il se transforme en UDID. Clic droit pour le copier.
- **Depuis l'iPhone** : ouvre un site comme udid.tech dans Safari et suis les instructions. Il installe un profil temporaire qui affiche l'UDID. Supprime ensuite ce profil (Réglages > Général > VPN et gestion de l'appareil).

## 4. Créer le jeton Diawi

Crée un compte sur diawi.com. Dans ton profil, rubrique « API access token », génère un jeton et copie-le.

## 5. Renseigner les secrets GitHub

Sur la page du dépôt : Settings > Secrets and variables > Actions > **New repository secret**. Crée un secret par ligne :

| Nom | Valeur |
|---|---|
| `ASC_KEY_ID` | le Key ID de la clé d'API |
| `ASC_ISSUER_ID` | l'Issuer ID |
| `ASC_KEY_P8` | le **contenu** du fichier `.p8` : ouvre-le avec un éditeur de texte et copie tout, lignes `-----BEGIN…` et `-----END…` comprises |
| `DEVELOPMENT_TEAM` | ton Team ID |
| `IPHONE_UDID` | l'UDID de ton iPhone |
| `DIAWI_TOKEN` | ton jeton Diawi |

Facultatif : `BUNDLE_ID_PREFIX`, le préfixe des identifiants de l'app. Par défaut, c'est `fr.elmdigitalagency`. Garde la valeur par défaut, sauf si ce préfixe est déjà pris sur un autre compte.

## 6. Compiler

Sur GitHub, ouvre l'onglet **Actions**, choisis le workflow **« Installer sur mon iPhone »**, puis clique sur **Run workflow**. Cela marche aussi depuis le téléphone.

Compte 20 à 30 minutes. Une coche verte indique la réussite. En cas de croix rouge, ouvre le run : la rubrique « Échec » liste les erreurs (voir plus bas).

## 7. Installer sur l'iPhone

1. Sur l'iPhone, ouvre le run réussi dans Safari. En haut, le résumé affiche **un lien Diawi** : touche-le, puis touche « Install ».
2. **Première fois seulement** : active **Réglages > Confidentialité et sécurité > Mode développeur** (l'option apparaît après l'installation), puis accepte le redémarrage et confirme.
3. Ouvre **Quinze**. L'onboarding te guide : niveau, horaires, puis l'autorisation **Temps d'écran** et le choix des apps à restreindre.

Pour vérifier que le blocage marche, mets une leçon dans 20 minutes, choisis une app à bloquer et attends l'heure. Le protocole complet est dans `docs/tests/screen-time-test-plan.md`.

## Mettre à jour l'app

Relance le workflow et installe le nouveau lien. Attention : n'envoie plus d'ancien `quinze.zip` dans le dépôt, il remplacerait le code par sa version et effacerait les corrections faites depuis.

Le workflow **« Compiler (sans signature) »** se lance tout seul à chaque modification du code. Il vérifie que l'app compile, sans secret ni compte Apple, et ne crée aucun certificat. Tes progrès sont conservés : c'est la même app, mise à jour. La signature de développement est valable **un an**. Avant l'échéance, il suffit de recompiler.

## Problèmes fréquents

| Message dans « Échec » | Solution |
|---|---|
| `Secret … absent` | Un secret de l'étape 5 manque ou est mal nommé |
| `No profiles for '…' were found`, `Family Controls` ou `Authentication failed` | L'étape 2.4 n'est pas faite ou incomplète : sur developer.apple.com > Identifiers, ouvre les 4 identifiants (`…quinze`, `.monitor`, `.shieldconfig`, `.shieldaction`). Coche **Family Controls (Development)** et **App Groups**, puis associe le groupe `group.<préfixe>.quinze`. Relance |
| `PLA Update available` ou contrat | Accepte le dernier contrat sur developer.apple.com/account (« Consulter le contrat »). Relance |
| `maximum number of certificates` | developer.apple.com > Certificates : révoque les anciens certificats « Apple Development » créés par l'API. Relance |
| `device … not registered` ou l'installation échoue | L'UDID du secret ne correspond pas à l'iPhone : vérifie-le, puis relance |
| L'app s'installe mais ne s'ouvre pas | Le Mode développeur n'est pas activé (étape 7.2) |

## Plus tard : synchronisation et vrai professeur IA (facultatif)

Pour retrouver tes progrès sur un autre iPhone, ou avoir les explications de l'IA :
1. Crée le backend en suivant `docs/06-deploiement-backend.md` (Supabase gratuit, clé Anthropic payée à l'usage : quelques centimes par jour pour un seul utilisateur).
2. Ajoute les secrets `SUPABASE_URL` et `SUPABASE_ANON_KEY`, puis relance le workflow.

À l'ouverture, l'app te demandera de créer un compte. Tes progrès locaux sont gardés, puis envoyés au serveur à la première synchronisation.
