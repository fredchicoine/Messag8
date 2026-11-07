# Messag8

Logiciel pour envoyer du texte en plein écran sur un 2e moniteur, en temps réel (comme PowerPoint).
L'opérateur tape le message sur l'écran 1 et le participant le voit sur l'écran 2.

## Fonctions
- Texte en temps réel, ou envoi manuel (Ctrl/⌘ + Entrée)
- Police, taille fixe, gras, alignement
- Le texte rapetisse automatiquement seulement s'il dépasse l'écran
- Fond noir, blanc ou vert (cases à cocher) ou couleur au choix
- Texte blanc, noir ou jaune (cases à cocher) ou couleur au choix
- **FLASH** pour attirer l'attention du participant (nombre, vitesse, son)
- Masquer le texte et effacer
- Logo en bas à droite, modifiable (« Changer le logo… »)
- Les réglages sont mémorisés

## Windows — `Messag8-Win/`
- Code : `Messag8-Win/src/Messag8.cs` (C# WinForms, .NET Framework 4, inclus dans Windows)
- Compiler : double-cliquer sur `Messag8-Win/src/build.bat` → crée `Messag8-Win/Messag8.exe`
- Le .exe déjà compilé est disponible dans les *Releases* du dépôt.

Raccourcis : F5 flash · F8 masquer · F9 effacer · Ctrl+Entrée envoyer

## macOS — `Messag8-Mac/`
- Code : `Messag8-Mac/src/main.swift` (Swift / AppKit)
- Compiler sur le Mac : voir `Messag8-Mac/LISEZMOI.txt` (`xcode-select --install`, puis `bash src/build.sh`)

Raccourcis : ⌘F flash · ⌘B masquer · ⌘K effacer · ⌘↩ envoyer · ⌘E écran participant
