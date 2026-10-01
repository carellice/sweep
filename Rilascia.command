#!/bin/bash
# Double-click launcher for Scripts/release.sh: asks for the version and the
# kind of release, then runs the script.
cd "$(dirname "$0")"

REPO="${SWEEP_REPO:-carellice/sweep}"

finish() {
    echo
    read -n 1 -s -r -p "Premi un tasto per chiudere..."
    echo
    exit "${1:-0}"
}

echo "=== Rilascio di Sweep ==="
LAST="$(gh release view --repo "$REPO" --json tagName --jq .tagName 2>/dev/null)"
echo "Ultima release pubblicata: ${LAST:-nessuna}"
echo

read -r -p "Nuova versione (es. 1.2.0): " VERSION
VERSION="${VERSION#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Versione non valida: servono tre numeri, es. 1.2.0"
    finish 2
fi

echo
echo "  1) Pubblica la release"
echo "  2) Crea una bozza da controllare su GitHub"
echo "  3) Prova: compila e comprime senza pubblicare"
read -r -p "Scelta [1]: " CHOICE

ARGS=("$VERSION")
case "${CHOICE:-1}" in
    1) ;;
    2) ARGS+=(--draft) ;;
    3) ARGS+=(--dry-run) ;;
    *) echo "Scelta non valida."; finish 2 ;;
esac

echo
./Scripts/release.sh "${ARGS[@]}"
STATUS=$?

echo
if [ "$STATUS" = 0 ]; then
    echo "Fatto."
else
    echo "Rilascio non riuscito (codice $STATUS)."
fi
finish "$STATUS"
