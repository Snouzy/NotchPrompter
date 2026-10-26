# Prompteur face cam relié au studio (25/10/2026)

Besoin : dire face caméra tout un short ou certains passages, en lisant le texte au prompteur, puis obtenir le montage automatiquement. La prise reste rattachée à la vidéo dans le studio.

Décidé avec Mathias : un passage face cam est un **troisième type de retour** dans le studio (`type: "cam"`), à côté de Commentaire et Coupe. Les prises viennent de l'app (caméra du Mac ou iPhone en Continuity Camera) **ou** d'un fichier déposé (Osmo Pocket 3, téléphone).

## Étape 1 : studio (video-studio, branche feat/face-cam) ✅ 25/10
- [x] Bouton « Face cam » dans la transcription, dans la fenêtre de plage de la timeline et dans l'onglet du panneau, avec « ◎ Toute la vidéo ».
- [x] Carte du retour : état (À tourner ou Tournée), « Lire au prompteur », « Déposer une prise » (« Filmer ou choisir » au téléphone), lecteur de chaque prise, Retirer (le fichier reste sur le disque).
- [x] Pastille « Tournage » avec le nombre de passages à tourner, et une fenêtre qui les liste avec « Tout lire au prompteur ».
- [x] Prises envoyées en flux, rangées sur le Crucial (`<projet>/takes/<id>/`) ou, à défaut, dans `review/takes/` (ignoré par git). Dépôt d'un fichier sur une carte ou dans la fenêtre.
- [x] API du prompteur : `GET /api/short/:id/prompter?items=…`, lien `notchprompter://open?server=…&short=…&items=…`.
- [x] Prompt envoyé à Claude : « PAS ENCORE TOURNÉ, ne monte rien », ou bien « remplace le passage par la prise », avec le chemin et les temps des passages lus.
- [x] Responsive : téléphone (390 px), tablette ou portable (1024 px), bureau (1440 px). Vérifié par captures dans un Chrome sans fenêtre, sans débordement.
- [x] Tests : 3 nouveaux, 83 au total, tous verts.
- [x] Studio redémarré sur 8770 (25/10). Le 26/10 : temps des essais acceptés par l'envoi (`passages=`), message du prompteur mis à jour (commits f37da23, 9cca07d).

## Étape 2 : l'app (fork NotchPrompter) ✅ 26/10
- [x] Projet xcodegen (`project.yml`, id `com.snouzy.notchprompter`, équipe X46PFJFYKM, macOS 14). Le `.xcodeproj` reste ignoré par git.
- [x] Lien `notchprompter://open` (Apple Event, marche aussi quand le lien lance l'app). Studio local seulement (127.0.0.1, localhost, *.localhost).
- [x] Fenêtre du mode studio sous l'encoche (600 × 300, cachée des captures d'écran) : un passage à la fois, Filmer, décompte de 3 s, défilement, Recommencer (nouvel essai, la caméra continue), Pause, Suivant / Terminer, vitesse, aperçu caméra en miroir.
- [x] Caméra : automatique (iPhone en Continuity, sinon Mac) ou au choix dans le menu, micro au choix, 4K quand possible, un .mov par passage dans `~/Movies/NotchPrompter/<short>/`.
- [x] À la fin d'un passage, envoi au studio (`source=notchprompter`, `passages=[{i,t0,t1}]`), progression affichée. Fichier à la corbeille seulement après un envoi réussi, gardé sinon.
- [x] Raccourcis pendant la séance : ⌥⌘R filmer/arrêter, ⌥⌘→ suivant, ⌥⌘← précédent, ⌥⌘↩ recommencer, ⌥⌘P pause, ⌥⌘↑/↓ vitesse.
- [x] Code public réparé : il ne compilait pas (type `PrompterTextAlignment`, raccourcis globaux et un nom de police absents) et le défilement était cassé (minuteur jamais branché, calcul du temps faux, Pause et Play remettaient au début, molette ×100, éditeur décalé d'un caractère, activation à la voix sans effet).
- [x] Tests : 11 tests Swift sans app hôte (lien, texte, séance complète avec fausse caméra, envoi raté, défilement, rendus PNG hors écran) + bout à bout avec un vrai serveur du studio (`node scripts/e2e-studio.mjs`).
- [x] Installée dans /Applications (non lancée), lien enregistré sur cette copie seulement.
- [ ] À vérifier par Mathias : première prise réelle (autorisations caméra et micro, iPhone en Continuity).

## Étape 3 : montage
- [ ] Skills `short-editing`, `shorts-collage` et `codingbiceps-motion` : quand un retour Face cam a une prise, transcrire la prise (whisper), l'aligner sur le texte, couper aux pauses, garder la meilleure version de chaque phrase, insérer la caméra au format de la vidéo, puis `add-version` et `resolve`.

## Règles
- video-studio : commit et push sur une branche de travail après chaque étape vérifiée. NotchPrompter : commits seulement sur son « oui ».
- Licence NotchPrompter : usage personnel et non commercial, la mention de copyright reste.
