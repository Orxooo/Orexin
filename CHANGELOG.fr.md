# Historique des versions

[简体中文](CHANGELOG.md) · [繁體中文](CHANGELOG.zh-Hant.md) · [English](CHANGELOG.en.md) · [日本語](CHANGELOG.ja.md) · **Français** · [Deutsch](CHANGELOG.de.md) · [Español](CHANGELOG.es.md)

[Retour au README](README.fr.md)

Les paquets d’installation et les instructions de mise à niveau sont disponibles sur la [page des versions](https://github.com/Orxooo/Orexin/releases).

## V1.0.4 — 2026-10-26

- Correction des options de session écrasées par la politique d’écran. Le blocage de l’économiseur peut être désactivé séparément ; son activation sélectionne une politique compatible.
- L’autorisation d’accessibilité affiche son état et ouvre les Réglages Système. Le pointeur indique pourquoi son déplacement est en attente ou suspendu.
- Éditeur de règles réorganisé : champs étiquetés, options avancées repliables, actions Enregistrer et Annuler fixes, et moins de bordures et de zones de défilement imbriquées.

## V1.0.3 — 2026-10-25

- Ajout de « Messages et alertes », qui conserve les messages de mise à jour, d’anomalie du service, d’expiration des demandes, d’avertissement de fin de session et de protection thermique.
- Prise en charge des fenêtres d’alerte et des notifications macOS pour les événements importants, sans répéter les rappels ni afficher tardivement des alertes dont la cause a disparu.
- Recherche de mises à jour après le lancement, puis toutes les 6 heures. Chaque version n’est signalée qu’une fois ; le téléchargement et l’installation restent manuels.
- Mise à jour des instructions d’utilisation et des captures d’écran en chinois et en anglais.

## V1.0.2 — 2026-10-22

- Correction de l’impossibilité de fermer la fenêtre principale et le panneau d’accès rapide, ainsi que de l’indisponibilité du menu « Fermer » et de `⌘W`. La barre des menus et les tâches en arrière-plan restent actives après la fermeture des fenêtres.

## V1.0.1 — 2026-10-18

- Correction du clignotement chaque seconde du panneau de la barre des menus pendant le travail, des images rémanentes du texte et des sauts de mise en page.

## V1.0.0 — 2026-10-18

Première version stable.

- Ajout d’un service de tâches indépendant en arrière-plan : les commandes et les plans d’exécution continuent de fonctionner après la fermeture de l’interface.
- Ajout des plans d’exécution JSON, avec dépendances, exécution séquentielle ou parallèle, limite de concurrence, branches en cas d’échec et journaux pour chaque élément.
- Possibilité d’annuler les commandes d’un plan qui n’ont pas encore démarré. Les commandes déjà lancées continuent de s’exécuter, et le redémarrage du service ne relance pas les tâches.
- Harmonisation des boutons, des sélecteurs et des interrupteurs ; correction de la mise en page des cartes, des filtres et des journaux ; amélioration de l’affichage dans les fenêtres étroites et de l’utilisation au clavier.
- Correction du problème empêchant la CLI intégrée au paquet d’installation de démarrer le service en arrière-plan.

## V0.3.0 Preview.1 — 2026-10-18

La page de publication porte le nom V0.3.1 Preview ; le tag d’origine est `v0.3.0-preview.1` et la version de l’application est `0.3.0`.

- Ajout de règles avancées avec conditions imbriquées, priorités, maintien des conditions pendant une durée donnée, délai de réactivation et simulations.
- Ajout de l’analyse de l’alimentation pour consulter les assertions d’alimentation du système, les processus sources identifiables et la chronologie des événements.
- Ajout des profils de travail et de l’importation/exportation JSON, avec aperçu des différences, fusion ou remplacement. Les règles et scripts importés doivent être activés localement.
- La CLI prend en charge les profils de travail, la simulation des règles, les requêtes sur l’alimentation et l’importation/exportation de configurations.
- Correction de l’alignement et de la mise en page dans les fenêtres étroites sur la page de gestion des tâches, ainsi que des erreurs de compilation avec Xcode 26.3.

## V0.2.0 Preview — 2026-10-14

- Ajout de la gestion de tâches en parallèle, avec un code de sortie, des journaux et un état de maintien en éveil propres à chaque tâche.
- Ajout de la CLI intégrée `orexin`, qui permet d’exécuter des commandes, d’enregistrer des tâches externes, d’envoyer des signaux de présence et d’interroger l’état.
- La fin d’une tâche n’affecte pas les autres. Lorsque toutes les tâches ont réussi et qu’aucune autre source ne maintient le Mac éveillé, un compte à rebours de 60 secondes avant la mise en veille peut démarrer.
- Possibilité de libérer le maintien en éveil tâche par tâche ou pour toutes les tâches, sans interrompre les commandes en cours d’exécution.
- Ajustement de la mise en page des tâches et ajout des textes manquants dans les sept langues.

## V0.1.0 Preview — 2026-10-12

Première version de prévisualisation publique.

- Modes de travail en arrière-plan et sur le bureau, sessions programmées ou conditionnelles, réglage de la luminosité et extinction de l’écran.
- Déclenchement automatique, tâches de commande, protection thermique et contre la batterie faible, et historique local d’exécution.
- Panneau dans la barre des menus, trois thèmes, sept langues et sons de clic facultatifs.
- Recherche de mises à jour des versions de prévisualisation.
- Correction des demandes répétées de mise en veille après la fin d’une session programmée et du décalage horizontal lors du passage entre certaines pages.
- Publication sous licence GPL-3.0-only.
