<p align="center">
  <img src="Assets/README/cover.png" width="100%" alt="Orexin : une éclipse bleu nuit et des arcs ambrés. Restez éveillé. Reposez-vous à temps.">
</p>

# Orexin

[简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [English](README.md) · [日本語](README.ja.md) · **Français** · [Deutsch](README.de.md) · [Español](README.es.md)

[![Version](https://img.shields.io/github/v/release/Orxooo/Orexin?color=56d7df&label=release)](https://github.com/Orxooo/Orexin/releases/latest)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-8ba6b8)
[![CI](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml/badge.svg?branch=main)](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml)
[![GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-b7c8d6)](LICENSE)

Orexin est un utilitaire pour la barre des menus de macOS qui vous permet de choisir quand votre Mac reste éveillé et quand il peut se mettre en veille.

Utilisez-le pour les compilations, les téléchargements, les présentations ou les tâches de longue durée, sur votre bureau ou capot fermé. Les sessions programmées, les règles automatiques et les tâches de commande permettent de définir quand cesser de maintenir le Mac éveillé.

[Télécharger la dernière version](https://github.com/Orxooo/Orexin/releases/latest) · [Historique des versions](CHANGELOG.fr.md) · [Manuel d’utilisation](https://github.com/Orxooo/Orexin/wiki)

![Modes de travail d’Orexin avec le thème Tron, affichés en chinois simplifié](Assets/README/orexin-1.0.3-modes.png)

## Fonctionnalités

- **Modes de travail :** le mode Travail en arrière-plan empêche la mise en veille lorsque le capot est fermé. Le mode Travail sur le bureau empêche la veille liée à l’inactivité, mais autorise la veille à la fermeture du capot.
- **Contrôle de l’écran :** réglez la luminosité à 0 %, conservez la luminosité normale, suivez le délai d’extinction défini par le système ou éteignez l’écran immédiatement. Chaque mode de travail mémorise son réglage.
- **Sessions de travail :** mettez fin à une session après une durée donnée, à une heure précise, à la fermeture d’une application ou d’un processus, ou à la fin d’un téléchargement.
- **Commandes et plans d’exécution :** exécutez des commandes en parallèle et consultez leurs codes de sortie et leurs journaux. Définissez en JSON les dépendances, les limites d’exécution simultanée et les branches à suivre en cas d’échec.
- **Règles automatiques et profils :** déclenchez le travail selon l’alimentation, les écrans, les périphériques, les applications, le réseau ou l’heure. Les conditions imbriquées, les simulations et l’importation/exportation de configurations sont pris en charge.
- **Protections et alertes :** activez, si nécessaire, la protection contre la batterie faible et la surchauffe, et consultez les alertes de service, les avertissements de fin de session et les rappels de mise à jour. Les notifications système et les fenêtres d’alerte dans l’application sont prises en charge. Les mises à jour s’installent manuellement.

Trois thèmes sont proposés : Tron, Zima Blue et Blade Runner 2049. L’application est disponible en chinois simplifié, chinois traditionnel, anglais, japonais, français, allemand et espagnol. Consultez la [liste des fonctionnalités](FEATURES.md) pour en savoir plus.

## Premiers pas

Nécessite un **Mac avec puce Apple Silicon et macOS 15 ou une version ultérieure**.

1. Téléchargez le paquet Apple Silicon (dont le nom se termine par `-arm64.zip`) depuis la [page des versions](https://github.com/Orxooo/Orexin/releases/latest), décompressez-le et déplacez `Orexin.app` dans Applications.
2. Ouvrez l’application, puis choisissez un mode de travail et une condition de fin. Pour travailler capot fermé, vous devez autoriser le service auxiliaire dans les Préférences.
3. Pour recevoir les notifications système, autorisez-les dans **Messages et alertes**, puis envoyez une alerte de test.

Le paquet est **signé avec un certificat Apple Development et n’a pas encore été notarié avec Developer ID**. Si macOS bloque le premier lancement, vérifiez la provenance du téléchargement, puis suivez les indications dans Confidentialité et sécurité. Il n’est pas nécessaire de désactiver SIP ni de désactiver Gatekeeper à l’échelle du système.

Pour vérifier le téléchargement, placez le fichier ZIP et le fichier `SHA256SUMS.txt` de la version dans le même répertoire :

```sh
shasum -a 256 -c SHA256SUMS.txt
```

### Mise à niveau

Attendez la fin des commandes et des plans d’exécution, mettez fin à toutes les demandes de maintien en éveil, puis arrêtez le service de tâches en arrière-plan :

```sh
/Applications/Orexin.app/Contents/Helpers/orexin service-stop
```

Quittez ensuite Orexin, remplacez l’application et relancez-la. Ignorez l’étape `service-stop` si votre ancienne version ne propose pas cette commande. Les préférences, l’historique et les journaux sont conservés ; les anciennes tâches ne sont pas relancées.

### Précautions d’utilisation

- L’option « Rester déverrouillé pendant le travail » nécessite une autorisation distincte. Elle désactive la demande de mot de passe à la sortie de veille pendant la session et rétablit la protection immédiate par mot de passe à la fin du travail. Orexin ne conserve aucun mot de passe et ne déverrouille pas un Mac déjà verrouillé.
- Une luminosité de 0 % n’équivaut pas à la mise en veille de l’écran. L’extinction de l’écran peut affecter les captures d’écran ou l’automatisation de l’interface qui en dépendent.
- Le retour au mode Veille normale libère uniquement les demandes de maintien en éveil d’Orexin. D’autres applications peuvent encore empêcher la veille.
- La protection thermique repose sur les niveaux de pression thermique de macOS, pas sur des températures en degrés Celsius. Le refroidissement ne relance pas automatiquement le travail arrêté.

## Gestion des tâches et CLI

Les commandes et les plans exécutés en arrière-plan continuent de fonctionner après la fermeture de l’interface. Les sessions manuelles et les règles automatiques nécessitent que le processus de l’interface reste actif. Après un redémarrage du service, les tâches inachevées sont signalées comme ayant perdu le contact et ne sont pas relancées automatiquement.

La CLI est intégrée au paquet de l’application et ne nécessite aucune installation supplémentaire :

```sh
orexin=/Applications/Orexin.app/Contents/Helpers/orexin
"$orexin" service-start
"$orexin" run --title Build -- make
"$orexin" list --json
```

Par défaut, la fin d’une commande libère la demande de maintien en éveil de cette tâche. Ajoutez `--after sleep` pour lancer un compte à rebours de 60 secondes avant la mise en veille après une réussite. Toutes les demandes qui se chevauchent doivent réussir, et aucune autre session ni règle ne doit encore demander le maintien en éveil. Libérer une demande ne met pas fin à sa commande.

L’autorisation de l’option « Rester déverrouillé pendant le travail » doit d’abord être accordée dans l’interface ; la CLI n’affiche pas de boîte de dialogue de mot de passe. Consultez le [guide de la CLI](docs/CLI.md) et le [guide des plans d’exécution](docs/EXECUTION-PLANS.md) pour les options, l’intégration de tâches externes et le format des plans.

## Compiler à partir des sources

Nécessite **Xcode 26+ et Swift 6**.

```sh
git clone https://github.com/Orxooo/Orexin.git
cd Orexin
swift test --arch arm64 --scratch-path /tmp/orexin-test-build
./scripts/build-app.sh
```

L’application est générée dans `/tmp/orexin-dist/Orexin.app` et utilise par défaut une signature ad hoc. Le fonctionnement capot fermé exige que l’application et le service auxiliaire soient signés avec le même certificat de développeur Apple :

```sh
OREXIN_SIGN_IDENTITY='Nom du certificat ou SHA-1' ./scripts/build-app.sh
```

Utilisez `OREXIN_BUILD_DIR` et `OREXIN_OUTPUT_DIR` pour définir les répertoires de compilation et de sortie. La CI est configurée avec Xcode 26.3 sur macOS 15 / 26 ; les résultats sont disponibles dans [Actions](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml).

## Documentation et retours

- [Profils de travail](docs/WORK-CONFIGURATION.md) · [Dictionnaire AppleScript](Resources/Orexin.sdef) · [Sécurité](SECURITY.md)
- [Signaler un problème](https://github.com/Orxooo/Orexin/issues/new/choose) · [Discussions](https://github.com/Orxooo/Orexin/discussions) · [Signalement privé de vulnérabilités](https://github.com/Orxooo/Orexin/security/advisories/new)
- [Guide de contribution](CONTRIBUTING.md) · [Code de conduite](CODE_OF_CONDUCT.md)

L’historique et les journaux locaux sont stockés dans `~/Library/Application Support/Orexin/`. Les anciennes données de WakeMac ne sont ni migrées ni supprimées automatiquement. Vérifiez que les journaux ne contiennent pas d’informations privées avant de les partager.

## Licence

[GPL-3.0-only](LICENSE) · © 2026 Orxooo. Les licences des ressources tierces sont indiquées dans [NOTICE](NOTICE).
