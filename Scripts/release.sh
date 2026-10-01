#!/bin/bash
# Builds Sweep and publishes it as a GitHub release with the GitHub CLI.
#
#   Scripts/release.sh 1.2.0            publish v1.2.0
#   Scripts/release.sh 1.2.0 --draft    create it as a draft to review on GitHub
#   Scripts/release.sh 1.2.0 --dry-run  build and zip only, publish nothing
#
# The target repository defaults to carellice/sweep; override with SWEEP_REPO.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${SWEEP_REPO:-carellice/sweep}"
VERSION=""
DRAFT=0
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --draft) DRAFT=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Opzione sconosciuta: $arg" >&2; exit 2 ;;
        *) VERSION="${arg#v}" ;;
    esac
done

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Uso: Scripts/release.sh <versione> [--draft] [--dry-run]   (es. 1.2.0)" >&2
    exit 2
fi
TAG="v$VERSION"
ZIP="build/Sweep-$VERSION.zip"

# --- Checks that must pass before anything is built -------------------------

TARGET=()
if [ "$DRY_RUN" = 0 ]; then
    command -v gh >/dev/null || { echo "GitHub CLI non trovata: brew install gh" >&2; exit 1; }
    gh auth status >/dev/null 2>&1 || { echo "Non hai effettuato l'accesso: gh auth login" >&2; exit 1; }
    if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
        echo "La release $TAG esiste già in $REPO." >&2
        exit 1
    fi

    if git rev-parse --git-dir >/dev/null 2>&1; then
        # The tag must point at exactly the code the app is built from.
        if [ -n "$(git status --porcelain)" ]; then
            echo "Ci sono modifiche non salvate in un commit: fai commit prima di rilasciare." >&2
            exit 1
        fi
        COMMIT="$(git rev-parse HEAD)"
        if ! gh api "repos/$REPO/commits/$COMMIT" >/dev/null 2>&1; then
            echo "Il commit ${COMMIT:0:7} non è su $REPO: fai git push prima di rilasciare." >&2
            exit 1
        fi
        TARGET=(--target "$COMMIT")
    else
        echo "Attenzione: questa cartella non è un repository git. Il tag $TAG punterà" >&2
        echo "al ramo predefinito di $REPO, che potrebbe non contenere questo codice." >&2
    fi
fi

# --- Build -------------------------------------------------------------------

swift test
VERSION="$VERSION" UNIVERSAL=1 ./Scripts/build-app.sh

rm -f "$ZIP"
ditto -c -k --keepParent build/Sweep.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "Archivio: $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
echo "SHA-256:  $SHA"

if [ "$DRY_RUN" = 1 ]; then
    echo "Prova completata: nessuna release pubblicata."
    exit 0
fi

# --- Publish -----------------------------------------------------------------

NOTES="build/release-notes.md"
cat > "$NOTES" <<EOF
## Installazione

1. Scarica \`Sweep-$VERSION.zip\`, decomprimilo e sposta **Sweep** in Applicazioni.
2. L'app non è notarizzata da Apple: al primo avvio macOS la blocca. Apri
   Impostazioni di Sistema → Privacy e sicurezza e premi **Apri comunque**, oppure esegui:

   \`\`\`bash
   xattr -dr com.apple.quarantine /Applications/Sweep.app
   \`\`\`

Richiede macOS 14 o successivo, Apple silicon o Intel.

SHA-256: \`$SHA\`
EOF

FLAGS=(--repo "$REPO" --title "Sweep $VERSION" --notes-file "$NOTES" --generate-notes)
[ "$DRAFT" = 1 ] && FLAGS+=(--draft)

gh release create "$TAG" "$ZIP" "${FLAGS[@]}" ${TARGET[@]+"${TARGET[@]}"}
