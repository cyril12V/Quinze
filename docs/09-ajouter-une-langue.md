# Ajouter une langue (exemple : l'arabe)

L'architecture est multilingue dès la V1 (§19).
- Chaque langue a ses propres contenus (`Content/<code>/`), son propre bundle (`<code>.json`), ses lignes dans `languages` et ses états de progression (`user_languages`, `memory_states` rattachés à des unités préfixées par la langue).
- Le moteur ne contient aucune règle propre à une langue en dehors du module de normalisation.

## 1. Contenu

1. Crée le plan de la langue en copiant `tools/curriculum_source.py` vers `tools/curriculum_ar.py`.
   - Définis `language` : `code: "ar"`, `writingDirection: "rtl"`, `ttsLocale: "ar-SA"` ou la variante retenue.
   - Définis les modules, les notions avec leurs prérequis, les leçons et le vocabulaire.
   - Préfixe tous les identifiants : `ar.gNN.slug`, `ar.v.slug`, `ar.lNN`.
2. Décide de la variété enseignée : arabe standard moderne ou dialecte (§19 : décision ultérieure). Elle conditionne le vocabulaire, l'audio et les réponses acceptées.
3. Rédige `Content/ar/source/mNN/…` au même format (`Content/SCHEMA.md`) :
   - la langue étudiée est dans `text`, la traduction française dans `translation` ;
   - `promptLanguage` vaut `ar` ou `fr`.
4. Rends le validateur générique. `tools/build_content.py` suppose encore `en.` pour les identifiants de diagnostic et les fiches de dictionnaire (`en.d.`, `en.diag`, `en.assess`) : remplace ces préfixes par `f"{lang}."`. C'est une petite modification.
5. Lance `python3 tools/build_content.py --lang ar` : le script produit `Content/build/ar.json`, `App/Resources/Content/ar.json` et `supabase/seed/content_ar.sql`.

## 2. Moteur (`Packages/LearningCore`)

La normalisation des réponses est aujourd'hui optimisée pour l'anglais : contractions, orthographe britannique ou américaine, nombres en lettres. Pour l'arabe, ajoute une normalisation spécifique, sélectionnée selon `language.code` :
- les **diacritiques (tashkīl)** sont facultatifs : les retirer avant de comparer, et signaler sans pénaliser les diacritiques faux ;
- unifier les variantes de lettres : alif (أ إ آ → ا), tā' marbūṭa / hā' (ة / ه) en fin de mot, yā' / alif maqṣūra (ي / ى), tatwīl (ـ) à supprimer ;
- les chiffres arabes orientaux (٠١٢…) équivalent aux chiffres occidentaux ;
- la ponctuation arabe (، ؛ ؟) est traitée comme la ponctuation latine ;
- la tolérance aux fautes de frappe se calcule après cette normalisation.

Ajoute des tests unitaires dédiés et un `RealContentTests` paramétré par langue.

## 3. App iOS

- **Choix de la langue** (onboarding, étape 3) : la liste vient de `languages`, avec `is_available = true` côté serveur et un bundle présent dans l'app. Retire la mention « bientôt » de l'arabe.
- **RTL** : les phrases dans la langue étudiée doivent être affichées avec `.environment(\.layoutDirection, .rightToLeft)` et un alignement à droite quand `language.writingDirection == .rtl`. `TappableSentenceView`, les champs de saisie et la remise en ordre sont concernés. L'interface reste en français, donc en gauche-à-droite.
- **Saisie** : afficher un message invitant à activer le clavier arabe si nécessaire. Le clavier ne peut pas être imposé, mais `keyboardType` et `textContentType` aident.
- **Audio** : `AVSpeechSynthesisVoice(language: "ar-SA")` existe sur iOS. Prévois des enregistrements validés pour les sons difficiles (§11.4, §19).
- **Progression** : un utilisateur peut étudier plusieurs langues ; `user_languages` contient une ligne par langue. L'accueil affiche la langue active.

## 4. Backend

1. Charge `supabase/seed/content_ar.sql`.
2. Dépose `ar/<version>.json` dans le bucket `content`.
3. Passe `languages.is_available` à `true` pour `ar`.

Le prompt du professeur IA reçoit déjà `languageCode` ; vérifie que ses consignes restent pertinentes pour l'arabe, en particulier les explications de morphologie et de racines.

## 5. Vérifications

- Le validateur et `swift test` passent.
- Diagnostic et première leçon testés sur iPhone, en mode clair et sombre, avec VoiceOver (lecture de l'arabe).
- Relecture linguistique par un enseignant d'arabe francophone.
