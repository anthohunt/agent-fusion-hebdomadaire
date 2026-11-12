#!/bin/bash
# Agent de fusion hebdomadaire : agent permanent (décision de l'utilisateur du 12/11/2026).
# Chaque samedi à 20 h (heure de Paris), il prend un poste de travail libre, y lance un agent Claude qui
# fusionne dans la branche principale toutes les branches qui passent sans conflit et réussissent les tests, suit
# l'agent jusqu'à la fin, rapatrie son rapport, efface la copie de travail du poste, rend le poste, puis dépose un
# signal pour le manager qui remonte le rapport. Rattrapage le dimanche matin seulement si le samedi n'a rien rendu.
#
# Usage : lancer.sh            passage normal (crontab)
#         RATTRAPAGE=1 lancer.sh   rattrapage du dimanche (ne fait rien si le rapport de la veille existe)
#         lancer.sh essai      montre les réglages et la consigne du jour, ne réserve aucun poste, ne lance rien
#
# Réglages de l'installation, hors dépôt (reglages.local, à côté de ce fichier) :
#   PROJET (nom affiché), NOM (nom de l'agent sur le poste), RAPPORTS (dossier des rapports, un sous-dossier par jour),
#   GESTIONNAIRE (outil qui prête et reprend les postes : demander / rendre), SIGNAUX (fichier JSONL lu par le
#   manager), POSTES (postes à essayer, dans l'ordre), LANCEUR_POSTE (lance un agent sur un poste : hôte, nom,
#   consigne), DEPOT (adresse git du projet), UNITY (version de l'éditeur), CLONES_INTERDITS (copies du poste à ne
#   jamais toucher), PREFIXE_TACHE (préfixe de la tâche planifiée que pose le lanceur, retirée à la fin) et la
#   fonction hote_de (nom de poste → alias ssh).
set -u
ICI=$(cd "$(dirname "$0")" && pwd)
PROJET="projet"; NOM="fusion"; RAPPORTS="$ICI/donnees"; GESTIONNAIRE=""; SIGNAUX="$ICI/donnees/signaux.jsonl"
POSTES=""; LANCEUR_POSTE=""; DEPOT=""; UNITY=""; CLONES_INTERDITS="aucune"; PREFIXE_TACHE="agent-"
hote_de() { echo "$1"; }
[ -f "$ICI/reglages.local" ] && . "$ICI/reglages.local"

J=$(TZ=Europe/Paris date +%F); N=$NOM; R="$RAPPORTS/$J"
consigne() {  # consigne du jour, réglages remplis (python : les chemins Windows gardent leurs barres obliques inverses)
  python3 - "$ICI/consigne.md" "$N" "$J" "$DEPOT" "$UNITY" "$CLONES_INTERDITS" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
for cle, val in zip(("NOM", "DATE", "DEPOT", "UNITY", "CLONES_INTERDITS"), sys.argv[2:]):
    t = t.replace("{{%s}}" % cle, val)
sys.stdout.write(t)
PY
}
if [ "${1:-}" = essai ]; then
  echo "projet=$PROJET nom=$N rapports=$R postes=[$POSTES]"
  for v in $POSTES; do echo "  $v → $(hote_de "$v")"; done
  echo "----- consigne du $J -----"; consigne; exit 0
fi
for v in GESTIONNAIRE POSTES LANCEUR_POSTE DEPOT UNITY; do
  [ -n "${!v}" ] || { echo "réglage manquant dans reglages.local : $v"; exit 2; }
done
mkdir -p "$R"
# Rattrapage du dimanche : rien si le passage du samedi a rendu son rapport
if [ -n "${RATTRAPAGE:-}" ] && [ -s "$RAPPORTS/$(TZ=Europe/Paris date -d yesterday +%F)/RAPPORT.md" ]; then exit 0; fi
signal(){  # signal pour le manager + une ligne au journal des passages (lu par le tableau des agents)
  python3 -c 'import json,sys,datetime; print(json.dumps({"date":datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),"genre":sys.argv[1],"texte":sys.argv[2]},ensure_ascii=False))' "$1" "$2" >> "$SIGNAUX"
  echo "$(TZ=Europe/Paris date '+%F %T') $2" >> "$RAPPORTS/journal.log"; }

V=""; for v in $POSTES; do
  python3 "$GESTIONNAIRE" demander "$v" --nom "$N" --besoin "agent de fusion hebdomadaire $PROJET (fusion des branches, tests, rapport)" 2>&1 | grep -q '^ACCORDÉ' && { V=$v; break; }
done
[ -n "$V" ] || { signal rapport-fusion "Fusion $PROJET du $J : aucun poste libre, nouvel essai dimanche matin."; exit 0; }
H=$(hote_de "$V")
consigne > "$R/consigne.md"
"$LANCEUR_POSTE" "$H" "$N" "$R/consigne.md" >> "$R/lancement.log" 2>&1

# Suivi : fin.txt écrit par l'agent, ou processus claude disparu ; 10 h au plus
sleep 30; PID=$(ssh -o BatchMode=yes "$H" "powershell -NoProfile -Command \"(Get-CimInstance Win32_Process | ? { \$_.Name -eq 'claude.exe' -and \$_.CommandLine -match '-p' } | Sort CreationDate -Desc | Select -First 1).ProcessId\"" | tr -d '\r')
for i in $(seq 1 600); do
  ssh -o BatchMode=yes "$H" "powershell -NoProfile -Command \"Test-Path C:\\agents\\$N\\fin.txt\"" 2>/dev/null | grep -q True && break
  ssh -o BatchMode=yes "$H" "powershell -NoProfile -Command \"if (Get-Process -Id $PID -EA 0) {'vit'} else {'mort'}\"" 2>/dev/null | grep -q mort && break
  sleep 60
done
scp -q "$H:C:/agents/$N/RAPPORT.md" "$H:C:/agents/$N/log.txt" "$H:C:/agents/$N/fin.txt" "$R/" 2>/dev/null
if [ -s "$R/RAPPORT.md" ]; then
  ssh -o BatchMode=yes "$H" "powershell -NoProfile -Command \"Remove-Item C:\\agents\\$N -Recurse -Force -EA 0; Unregister-ScheduledTask $PREFIXE_TACHE$N -Confirm:\\\$false -EA 0\"" >/dev/null 2>&1
  signal rapport-fusion "Fusion $PROJET du $J finie sur $V : rapport $R/RAPPORT.md"
else
  signal rapport-fusion "Fusion $PROJET du $J sur $V : pas de rapport (agent arrêté ?), copie gardée sur le poste ; journal $R/log.txt"
fi
python3 "$GESTIONNAIRE" rendre "$V" --nom "$N" >/dev/null 2>&1
