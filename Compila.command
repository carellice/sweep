#!/bin/bash
# Double-click launcher for Scripts/build-app.sh: builds build/Sweep.app and
# shows it in the Finder.
cd "$(dirname "$0")"

./Scripts/build-app.sh
STATUS=$?

echo
if [ "$STATUS" = 0 ]; then
    open -R build/Sweep.app
else
    echo "Compilazione non riuscita (codice $STATUS)."
fi
read -n 1 -s -r -p "Premi un tasto per chiudere..."
echo
exit "$STATUS"
