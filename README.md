# DeskWidgets

Widgets natifs pour le bureau du Mac, construits sans Xcode. Le premier suit l'avancement de tes projets : un résumé d'un coup d'oeil, et un clic pour les détails.

## Comment ça marche

Trois étages, qui ne se connaissent que par un fichier JSON :

1. **Le collecteur** (`collector/collect_projects.py`) passe voir chaque projet et écrit `~/Library/Application Support/DeskWidgets/projects.json`.
2. **DeskKit** (`Sources/DeskKit`) est le socle commun : fenêtre posée sur le bureau, thème, barres et anneaux, lecture du JSON avec mise à jour automatique.
3. **Les widgets** (`Sources/ProjectsWidget`, ...) ne font que dessiner ce que contient le JSON.

L'avancement vient des cases à cocher `- [ ]` / `- [x]` du premier fichier qui en contient parmi `TACHES.md`, `TODO.md`, `TASKS.md`, `ROADMAP.md`, `contexte.md`. Les tâches barrées (`~~texte~~`) ne comptent pas. Sans cases, le projet s'affiche sans pourcentage, avec sa date d'activité (dernier commit ou dernière modification de `JOURNAL.md`).

## Installation

Il faut les outils en ligne de commande d'Apple (pas Xcode). Pour vérifier : `swift --version`. Sinon : `xcode-select --install`.

```bash
cd "<ce dossier>"
python3 collector/collect_projects.py --verbose   # écrit projects.json et affiche un tableau
bash scripts/build_app.sh                        # compile et crée dist/DeskWidgets.app
open dist/DeskWidgets.app                        # le widget apparaît en haut à droite
```

## Démarrage automatique

`bash scripts/install_agents.sh` crée deux tâches de fond dans `~/Library/LaunchAgents` : le widget se lance à chaque ouverture de session, et le collecteur met les données à jour toutes les 15 minutes.

Pour désactiver le lancement du widget au besoin, deux boutons :
- en bas de la vue détail : « Lancement au démarrage : activé / désactivé » (un clic pour basculer) ;
- clic droit sur le widget : « Lancer au démarrage » (coché si activé).

Désactiver supprime le fichier `com.noham.deskwidgets.app.plist` : le widget ne reviendra plus au prochain redémarrage, mais reste affiché jusqu'à ce que tu le quittes. Le collecteur continue de tourner (sans effet visible). Pour tout retirer : `bash scripts/uninstall_agents.sh`.

Pour tester la lecture des données sans ouvrir de fenêtre : `dist/DeskWidgets.app/Contents/MacOS/DeskWidgets --check`.

## Utilisation

- Un clic sur le widget le déplie, un clic sur l'en-tête le replie.
- Un clic sur un projet (vue détail) ouvre son dossier dans le Finder.
- Tu peux le déplacer en le faisant glisser. Sa place est retenue.
- Clic droit : Actualiser, Couleurs du fond d'écran, Lancer au démarrage, Quitter.

## Couleurs

L'accent (barres, anneaux, pastilles) prend la teinte dominante de ton fond d'écran, en version claire ou sombre selon le mode du Mac. Le fond flou de la carte laisse déjà passer les tons du fond d'écran. L'analyse se refait quand le fond d'écran change ou quand tu changes d'espace. Le orange des avertissements (projet calme, données anciennes) reste orange, sauf si l'accent est déjà orange : il passe alors au rouge.

Clic droit, « Couleurs du fond d'écran » : coche ou décoche. Décoché, ou si le fond d'écran n'a presque pas de couleur (gris, noir et blanc), ou s'il s'agit d'un diaporama, l'accent reste vert d'eau.

## Réglages

`config/projects.json` : dossiers à parcourir (`roots`), projets à ignorer (`exclude`), noms courts (`display_names`), seuils d'activité (`thresholds_days` : actif sous 7 jours, calme sous 30, en veille au-delà).

## Ajouter un futur widget

1. Écrire un collecteur qui produit son propre JSON dans `~/Library/Application Support/DeskWidgets/` (n'importe quel langage).
2. Créer un dossier `Sources/MonWidget` avec ses vues SwiftUI, construites avec les briques de DeskKit (`WidgetCard`, `ProgressRing`, `ProgressBar`, `FeedStore`...), et une fonction qui renvoie un `DeskWidgetDescriptor`.
3. Déclarer la cible dans `Package.swift` et ajouter deux lignes dans `Sources/DeskWidgets/DeskWidgetsApp.swift`.

## Limites connues

- Ce n'est pas un widget de la galerie macOS (centre de notifications, "Modifier les widgets") : c'est une fenêtre native posée sur le bureau. Les vues SwiftUI pourront être reprises telles quelles dans un vrai widget WidgetKit le jour où Xcode sera disponible.
- Le code est compilé et lancé à chaque envoi sur GitHub (Actions, sur un Mac avec Swift 6.3), avec une capture du résumé et du détail sur un fond d'écran bleu. Ce test ne simule pas un vrai clic de souris, un glisser, ni un redémarrage.
- Pour avoir l'app sans compiler : onglet Actions du dépôt, dernier test, artefact `DeskWidgets-app`. Après décompression, macOS la bloque car elle vient d'internet ; la commande `xattr -dr com.apple.quarantine DeskWidgets.app` la débloque.
- Le geste "cliquer sur le fond d'écran pour afficher le bureau" peut écarter le widget avec les autres fenêtres. Cela n'a pas été testé.
