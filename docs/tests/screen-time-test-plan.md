# Plan de test sur appareil — blocage Screen Time

Ces cas ne peuvent pas être joués en CI ni dans le simulateur (Family Controls n'y fonctionne pas). Ils se jouent sur **iPhone physique** avec un build TestFlight (voir `docs/07-ci-testflight-sans-mac.md`). Les tests unitaires de la machine à états (`App/Tests/ScreenTime/`) tournent en CI et couvrent la logique ; ce plan couvre le comportement du système iOS.

## Conventions

- **Planning de test** : créneaux Matin, Après-midi, Soir à des heures proches de l'heure courante (par exemple H+10, H+40, H+70 minutes), fenêtre de sécurité de 15 à 30 minutes, délai de rappel « leçon non terminée » de 5 minutes.
- **Sélection de test** : 2 apps distrayantes, 1 catégorie entière, 1 site web.
- **Appareils** : au moins deux iPhones, iOS 17 et iOS 18 si possible. Noter modèle, version d'iOS, version et numéro de build.
- **Preuves** : capture ou enregistrement d'écran daté pour chaque cas ; heure réelle d'activation relevée à la minute (et retard par rapport à l'heure prévue).
- **Résultat** : OK, KO, ou Partiel (avec commentaire). Tout KO sur un cas marqué **[Bloquant]** déclenche l'examen des critères no-go de `docs/02-faisabilite-apple.md` §8.
- Entre deux cas : retirer le jour courant de l'état (réglages > désactiver puis réactiver la fonctionnalité) pour repartir d'un état propre.

## 1. Autorisation Temps d'écran

| Id | Situation | Étapes | Résultat attendu |
|---|---|---|---|
| A1 | Autorisation accordée | Écran de sélection > « Autoriser Temps d'écran » > valider | État « autorisé » ; la sélection est possible ; la surveillance peut être activée |
| A2 | Autorisation refusée / annulée | Annuler la fenêtre système ; puis la refuser | Message clair (« annulée », « refusée ») ; aucun bouclier ; bouton « Ouvrir les Réglages » ; l'app reste utilisable |
| A3 | Révoquée, app fermée **[Bloquant]** | Réglages > Temps d'écran > Apps avec accès à Temps d'écran > retirer Quinze, sans ouvrir Quinze ; attendre un créneau ; ouvrir Quinze | Aucune restriction pendant le créneau ; à l'ouverture : état « refusée », message d'avertissement, notification « Les restrictions ne fonctionnent plus » ; shield levé |
| A4 | Révoquée pendant un bouclier actif | Créneau actif, retirer l'accès, revenir dans Quinze | Les apps ne sont plus restreintes ; état du créneau cohérent (levé, pas « actif ») |
| A5 | Rétablie | Réaccorder l'autorisation pendant une fenêtre encore ouverte | La restriction reprend dans la fenêtre si la leçon n'est pas faite |
| A6 | Pas de code de verrouillage / pas de compte iCloud | Si possible, tester un iPhone sans code | Message explicite (code ou iCloud requis), pas de plantage |
| A7 | Simulateur / entitlement absent | Lancer le build du simulateur | État « indisponible », les leçons fonctionnent sans restriction |

## 2. Activation selon l'état de l'app

| Id | Situation | Étapes | Résultat attendu |
|---|---|---|---|
| B1 | App ouverte au premier plan à l'heure du créneau | Rester dans Quinze jusqu'à l'heure | Quinze reste utilisable ; les apps choisies sont restreintes à l'heure ; `activeSlots` mis à jour au `reconcile` |
| B2 | App en arrière-plan | Utiliser une app choisie pendant l'heure du créneau | Le bouclier apparaît sur l'app choisie, sans ouvrir Quinze |
| B3 | App fermée (retirée du sélecteur) **[Bloquant]** | Forcer la fermeture ; attendre l'heure | Restriction à l'heure (± 2 min), sans ouvrir Quinze |
| B4 | iPhone verrouillé à l'heure | Verrouiller 5 minutes avant ; déverrouiller après l'heure | Bouclier présent sur l'app choisie |
| B5 | Créneau atteint pendant l'utilisation d'une app choisie | Utiliser l'app au moment pile | L'app passe sous bouclier (noter le délai) |
| B6 | Mise en route de la surveillance dans la fenêtre | Activer la fonctionnalité alors que l'heure courante est dans la fenêtre | Le bouclier s'applique (par le moniteur ou par `reconcile`), une seule fois ; l'échéance est la fin de fenêtre |

## 3. Écran de restriction

| Id | Étapes | Résultat attendu |
|---|---|---|
| C1 | Ouvrir une app restreinte | Titre « Leçon de HH:mm en attente » (heure du créneau actif), sous-titre « Fais ta leçon de 5 minutes dans Quinze pour débloquer tes apps. », boutons « Compris » et « Déblocage d'urgence » ; lisible en mode sombre et avec texte agrandi |
| C2 | Toucher « Compris » | Le bouclier se ferme (retour à l'écran d'accueil) ; notification « Ouvre Quinze pour faire ta leçon » reçue dans les secondes qui suivent |
| C3 | Toucher « Déblocage d'urgence » | Voir H1 |
| C4 | Catégorie et site web restreints | Ouvrir une app de la catégorie, ouvrir le site dans Safari | Même bouclier sur l'app de la catégorie et sur le site |
| C5 | Deux créneaux actifs | Voir J1 | Titre « Leçons en attente » |

## 4. Validation de la leçon

| Id | Situation | Étapes | Résultat attendu |
|---|---|---|---|
| D1 | Leçon validée avec des erreurs **[Bloquant]** | Créneau actif ; ouvrir Quinze ; faire la leçon avec des erreurs, terminer les corrections | Statut « terminée » ; apps utilisables immédiatement ; 100 % de réussite non exigé |
| D2 | Leçon non validée | Quitter la leçon avant la fin | Les apps restent restreintes ; la leçon est reprenable |
| D3 | Départ anticipé (pré-validation) | Faire la leçon du créneau suivant avant son heure (dans la fenêtre « départ anticipé », 60 min par défaut) | À l'heure du créneau, aucune restriction (le moniteur voit le créneau validé) |
| D4 | Validation d'un seul créneau | A et B actifs ; valider A | A est levé, B reste restreint (stores indépendants) |
| D5 | Validation app en arrière-plan | Valider, mettre Quinze en arrière-plan, ouvrir l'app restreinte | Pas de bouclier ; notification de confirmation si l'option est activée |
| D6 | Validation puis fin de fenêtre | Valider A, attendre la fin de la fenêtre de A | A reste « levé par validation » (pas « expiré ») |

## 5. Changement de planning

| Id | Situation | Étapes | Résultat attendu |
|---|---|---|---|
| E1 | Heure modifiée hors créneau actif | Décaler un créneau futur | Nouvelle heure appliquée ; l'ancienne n'active plus rien ; notifications reprogrammées |
| E2 | Heure modifiée pendant un bouclier actif | Décaler le créneau actif | Pas de bouclier orphelin ; au plus une application selon la nouvelle fenêtre |
| E3 | Créneau déjà expiré puis déplacé dans le futur proche | Laisser expirer, déplacer la fenêtre sur l'heure courante | La restriction repart dans la nouvelle fenêtre |
| E4 | Fonctionnalité désactivée | Désactiver « Restreindre les apps pendant les leçons » pendant un bouclier | Tous les boucliers levés, surveillance arrêtée, plus rien aux créneaux suivants |
| E5 | Planning invalide (créneaux trop proches, fenêtre < 15 min) | Tenter d'enregistrer | Refus clair, restrictions précédentes inchangées |
| E6 | Changement de sélection pendant un bouclier | Ajouter/retirer une app | Le bouclier actif suit la nouvelle sélection |

## 6. Fuseau horaire et heure

| Id | Situation | Étapes | Résultat attendu |
|---|---|---|---|
| F1 | Changement de fuseau, app ouverte | Réglages > Général > Date et heure > fuseau différent | La surveillance est relancée ; les créneaux restent aux mêmes heures murales locales |
| F2 | Changement de fuseau, app fermée | Changer le fuseau, rouvrir Quinze | À l'ouverture : surveillance relancée, aucun bouclier orphelin |
| F3 | Changement d'heure (été / hiver) | Régler manuellement la date au passage à l'heure d'été puis d'hiver | Un créneau situé dans l'heure inexistante ou répétée ne reste pas actif au-delà de son échéance |
| F4 | Heure réglée manuellement vers le passé / futur | Avancer l'horloge de 3 h pendant un bouclier | Le bouclier est levé au plus tard au prochain `reconcile` ; aucun bouclier sans échéance |
| F5 | Passage de minuit | Créneau tardif (fenêtre bornée à 23:59) | La fenêtre ne traverse jamais minuit ; le lendemain repart propre |

## 7. Redémarrage

| Id | Situation | Étapes | Résultat attendu |
|---|---|---|---|
| G1 | Redémarrage avant un créneau | Redémarrer l'iPhone, ne pas ouvrir Quinze, attendre l'heure | Restriction à l'heure (surveillance persistante) |
| G2 | Redémarrage pendant un bouclier actif **[Bloquant]** | Redémarrer pendant le créneau, ne pas ouvrir Quinze | Le bouclier est soit toujours actif, soit levé ; dans tous les cas levé à la fin de la fenêtre (± 5 min) sans ouvrir l'app |
| G3 | Redémarrage après validation | Valider, redémarrer | Aucun bouclier réapparaît pour ce créneau ce jour-là |
| G4 | Plantage de l'app | Forcer l'arrêt pendant la leçon puis rouvrir | `reconcile` : état cohérent, boucliers périmés levés, bouclier réappliqué si la fenêtre est active et la leçon non faite |

## 8. Déblocage de secours

| Id | Étapes | Résultat attendu |
|---|---|---|
| H1 | Depuis le bouclier : « Déblocage d'urgence » | Bouclier fermé ; tous les créneaux actifs levés en moins de 5 s ; apps utilisables |
| H2 | Depuis l'app (réglages ou écran dédié) | Même résultat ; confirmation affichée |
| H3 | Journal | L'événement (date, raison, créneaux) est enregistré ; les 50 derniers sont conservés |
| H4 | Après le secours | Pas de réapplication le même créneau (ni par `reconcile` ni par redémarrage de la surveillance) ; le créneau suivant fonctionne normalement |
| H5 | Secours sans bouclier actif | Aucun effet de bord ; entrée de journal vide |
| H6 | Secours dans la fenêtre avant l'exécution du moniteur | Le créneau n'est pas restreint juste après |

## 9. Échéance de sécurité

| Id | Situation | Étapes | Résultat attendu |
|---|---|---|---|
| I1 | Leçon jamais faite, app jamais ouverte **[Bloquant]** | Laisser la fenêtre se terminer | Bouclier levé à l'heure de fin (± 2 min) sans aucune action ; à la réouverture : état « expiré » |
| I2 | Fenêtre minimale (15 min) | Régler la fenêtre à 15 minutes | Levée à H+15 ; aucune erreur `intervalTooShort` |
| I3 | Fenêtre maximale (240 min) | Régler 240 min en début de journée | Levée à H+240 ou 23:59 au plus tard |
| I4 | Le lendemain d'un créneau expiré | Attendre le jour suivant | Le créneau est de nouveau planifié normalement |
| I5 | Mesure d'un bouclier oublié | Si un bouclier dépasse l'échéance : relever la durée de dépassement et si l'ouverture de l'app le lève | Donnée de décision pour le risque R2 |

## 10. Plusieurs sessions dues

| Id | Situation | Étapes | Résultat attendu |
|---|---|---|---|
| J1 | Fenêtres qui se chevauchent | Après-midi à 14:00 et Soir à 15:00, fenêtres de 120 min | Entre 15:00 et 16:00 deux boucliers ; valider l'après-midi lève seulement ce créneau |
| J2 | Matin non fait, après-midi qui démarre | Laisser le matin expirer, attendre l'après-midi | Le matin reste « expiré » ; l'après-midi s'active indépendamment |
| J3 | Trois leçons dues en retard | Ouvrir Quinze tardivement après plusieurs créneaux | Seuls les créneaux dont la fenêtre est encore ouverte restreignent ; chacun se valide séparément |
| J4 | Même app dans la sélection de plusieurs créneaux | Valider un créneau pendant que l'autre est actif | L'app reste bloquée tant que le second est actif |

## 11. Conflits avec d'autres limites Temps d'écran

| Id | Situation | Étapes | Résultat attendu |
|---|---|---|---|
| K1 | Temps de repos Apple actif | Activer Temps de repos sur la même plage | Les deux coexistent ; lever Quinze ne lève pas le Temps de repos |
| K2 | Limite d'app Apple sur une app choisie | Limite quotidienne atteinte | Après validation de la leçon, l'app reste bloquée par la limite d'Apple (comportement attendu, hors du contrôle de Quinze) |
| K3 | Autre app de contrôle parental autorisée | Installer une app utilisant Family Controls | Message d'erreur explicite à l'autorisation (conflit), pas de plantage |
| K4 | Restrictions de contenu et de confidentialité | Activer une restriction d'app système | Quinze n'altère pas ces réglages |
| K5 | Mode de concentration (Focus) actif | Créneau pendant un Focus | Les boucliers s'appliquent normalement |

## 12. Modes de restriction et fonctions essentielles

| Id | Situation | Étapes | Résultat attendu |
|---|---|---|---|
| L1 | Mode « Bloquer les apps choisies » | Créneau actif | Seules les apps, catégories et sites choisis sont bloqués |
| L2 | Mode « Tout bloquer sauf les apps autorisées », Quinze autorisée **[Bloquant]** | Autoriser Quinze + 2 apps | Les autres apps sont bloquées ; Quinze, Téléphone, Réglages, appels d'urgence accessibles ; **relever la liste des apps système qui restent ouvertes** |
| L3 | Même mode sans aucune app autorisée | Tenter d'enregistrer | L'enregistrement est refusé ; aucun bouclier ne verrouille Quinze |
| L4 | Même mode, Quinze oubliée | Autoriser 2 apps sans Quinze | Quinze est bloquée : le secours depuis le bouclier fonctionne ; l'avertissement de l'écran de sélection est clair |
| L5 | Appel et numéros d'urgence | Pendant un bouclier | Passer un appel et composer un numéro d'urgence : possible |

## 13. Notifications

| Id | Étapes | Résultat attendu |
|---|---|---|
| N1 | Rappels de leçon | « Ta leçon d'anglais est prête. Cinq minutes pour progresser. » à chaque heure ; 7 jours programmés, moins de 64 en attente |
| N2 | Rappel « leçon non terminée » | Reçu après le délai si la leçon n'est pas faite ; absent si elle est faite |
| N3 | Soir avec révisions | Le texte du soir mentionne les révisions dues |
| N4 | Confirmation de validation | Si activée : reçue après validation app en arrière-plan |
| N5 | Alerte d'autorisation perdue | Voir A3 |
| N6 | Notification sans autorisation de notifications | Aucun plantage ; les restrictions fonctionnent quand même (elles ne dépendent pas des notifications) |

## 14. Performance et fiabilité

| Id | Mesure | Seuil |
|---|---|---|
| P1 | Retard d'activation moyen et maximal sur 7 jours, 2 appareils | ≥ 90 % des activations à moins de 2 minutes |
| P2 | Dépassement d'échéance | Aucun bouclier au-delà de 5 minutes après l'échéance |
| P3 | Durée du déblocage de secours | Moins de 5 secondes |
| P4 | Stabilité du moniteur (extension) | Aucune fenêtre manquée sur 7 jours ; noter tout créneau où le bouclier n'est pas apparu |
| P5 | Batterie | Aucune consommation anormale attribuée à Quinze dans Réglages > Batterie |

## Fiche de résultat (à copier pour chaque passe)

| Id | Date | Appareil / iOS | Build | Heure prévue | Heure réelle | Résultat | Commentaire / capture |
|---|---|---|---|---|---|---|---|
| A1 | | | | | | | |
