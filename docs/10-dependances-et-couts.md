# Dépendances, services externes et coûts récurrents

Tarifs relevés en octobre 2026. Les prix changent : vérifie les pages officielles avant de t'engager.

## Services externes

| Service | Usage | Indispensable |
|---|---|---|
| Apple Developer Program | Signature, TestFlight, App Store, entitlements Family Controls | Oui |
| Supabase | Postgres, Auth (e-mail et Apple), Edge Functions, Storage | Oui |
| API Claude (Anthropic) | Professeur IA et notation des réponses libres ambiguës | Non : l'app fonctionne sans, avec les explications du contenu |
| GitHub (Actions) | Compilation iOS sur macOS, tests, envoi TestFlight, sans Mac | Oui, en l'absence de Mac |
| Serveur e-mail SMTP (facultatif) | E-mails d'Auth en production ; celui de Supabase est très limité en volume | Recommandé |

## Dépendances logicielles

| Dépendance | Où | Licence |
|---|---|---|
| supabase-swift ≥ 2.5.0 (et ses dépendances : swift-crypto, swift-http-types, swift-concurrency-extras…) | App iOS | MIT |
| `npm:@supabase/supabase-js@2` | Edge Functions | MIT |
| XcodeGen | CI, génération du projet | MIT |
| fastlane (facultatif) | CI, envoi TestFlight | MIT |
| Frameworks Apple : SwiftUI, SwiftData, FamilyControls, ManagedSettings, DeviceActivity, UserNotifications, AVFoundation, AuthenticationServices, Network | App et extensions | SDK Apple |

Le moteur `LearningCore` n'a aucune dépendance externe.

## Coûts récurrents estimés

### Fixes

| Poste | Coût |
|---|---|
| Apple Developer Program | 99 $ par an |
| Supabase Free | 0 $ : suffisant pour développer et tester. Le projet est mis en pause après une semaine d'inactivité, ce qui est inadapté à la production |
| Supabase Pro | environ 25 $ par mois, avec quotas inclus généreux pour quelques milliers d'utilisateurs |
| GitHub Actions | Gratuit pour un dépôt public. Pour un dépôt privé, les minutes macOS sont décomptées avec un multiplicateur élevé : un build iOS prend 10 à 20 minutes, ce qui permet seulement quelques dizaines de builds par mois sur l'offre gratuite. Rendre le dépôt public, ou passer à une offre payante, lève cette limite |

### Variables : IA (Claude Haiku 5.5)

Tarif : 0,10 $ par million de tokens en entrée et 0,50 $ par million en sortie (prompts de moins de 100 000 tokens) ([source](https://platform.claude.com/docs/en/about-claude/pricing)).

Une explication consomme environ 1 500 tokens en entrée (consignes, exercice, règle, réponse) et 300 en sortie, soit environ **0,0003 $ par appel**.

| Hypothèse | Appels par mois | Coût mensuel |
|---|---|---|
| 100 utilisateurs actifs, 5 appels par jour | 15 000 | environ 4,5 $ |
| 1 000 utilisateurs actifs, 5 appels par jour | 150 000 | environ 45 $ |
| 10 000 utilisateurs actifs, 5 appels par jour | 1 500 000 | environ 450 $ (avant cache) |

Ce qui réduit ces montants :
- **Cache.** Les explications identiques (même exercice, même réponse, même niveau) sont servies depuis `ai_cache`, sans appel au modèle ni consommation de quota. Les erreurs fréquentes sont donc expliquées une fois pour tous.
- **Quota par utilisateur.** 40 appels par 24 h glissantes (`AI_DAILY_QUOTA`).
- **Plafond mensuel global.** 200 000 appels (`AI_MONTHLY_BUDGET_REQUESTS`) : au-delà, l'app sert les explications du contenu validé.
- **Correction locale d'abord.** La correction de niveau 1 se fait sur l'iPhone ; l'IA n'est consultée que pour les réponses libres incertaines ou à la demande (« Explique-moi »).

### Ordre de grandeur total

| Phase | Coût mensuel indicatif |
|---|---|
| Développement et tests (Supabase Free, peu d'IA, dépôt public) | environ 8 $ (abonnement Apple lissé) |
| Lancement, jusqu'à 1 000 utilisateurs actifs | environ 25 $ + 45 $ + 8 $, soit **80 $ par mois** |
| 10 000 utilisateurs actifs | Supabase Pro avec un peu de dépassement, plus IA plafonnée : **300 à 500 $ par mois** |

Non inclus : un domaine et un service e-mail transactionnel (environ 0 à 20 $ par mois), une éventuelle relecture linguistique professionnelle (ponctuelle), un éventuel compte Apple au nom d'une société (99 $ par an également, mais un numéro D-U-N-S est requis).
