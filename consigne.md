# Agent de fusion hebdomadaire

Décision de l'utilisateur (12/11/2026) : chaque samedi, fusionner dans la branche principale toutes les branches qui passent sans conflit et réussissent les tests, puis faire un court rapport des décisions à prendre. Critère validé : « un samedi soir, toutes les branches qui se fusionnent sans conflit sont dans master, le projet y compile et réussit ses tests ; rapport de quelques lignes : fusionnées, puis une décision par branche bloquée, avec les choix ».

## Travail (dossier C:\agents\{{NOM}}, mode autonome, aucune question)
1. Clone neuf de {{DEPOT}} dans C:\agents\{{NOM}}\projet (clé SSH du poste). Jamais une autre copie du poste ({{CLONES_INTERDITS}}).
2. Repère avant tout : tag `fusion/avant-{{DATE}}` sur origin/master, poussé (retour arrière en une commande).
3. Branches candidates : toutes les branches distantes sauf master qui ont des commits absents de master (toutes, sans exception).
4. Pour chaque candidate (de la plus ancienne à la plus récente) : fusion sans avance rapide dans une branche de travail locale.
   - Conflit → `git merge --abort`, la branche va au rapport (fichiers en conflit, auteurs, ce que chacun change, choix possibles).
   - Sans conflit → garder dans la pile.
5. Sur l'état fusionné : compilation Unity ({{UNITY}}) et tests EditMode en mode batch (`-runTests -testPlatform EditMode`), lancé par `Start-Process` de PowerShell, jamais depuis bash (sinon « Could not connect to IPC stream »). Les tests PlayMode (dont certains dépendent du réseau) ne sont pas lancés : écris-le dans le rapport. Si échec : retrouver la ou les branches fautives (retrait une par une), les sortir de la pile et les mettre au rapport, recommencer jusqu'au vert.
6. Pousser master (avance rapide sur le master du jour, jamais de --force). Si master a bougé entre-temps : refetch et recommencer l'étape 5 sur le nouveau master.
7. Ne supprimer aucune branche, ne rien envoyer vers un appareil, ne publier aucune version, rien sur le magasin d'applications.

## Silence
Aucun son : ne jamais remettre le son du poste, Unity en muet.

## Rapport : C:\agents\{{NOM}}\RAPPORT.md (le lanceur le rapatrie et le remonte à l'utilisateur)
Français, quelques lignes :
- **Fusionné** : branche → commit de fusion, une ligne chacune ; tag de repère ; résultat des tests (n réussis / n).
- **Décisions à prendre** : une par branche bloquée (conflit ou tests), en une phrase simple, puis choix A/B/C + « D — autre chose ».
- **Non traité** : ce qui n'a pas pu être fait et pourquoi.
