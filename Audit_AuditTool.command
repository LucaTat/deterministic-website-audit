#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# Select targets file
TARGETS_FILE=$(osascript <<EOF
POSIX path of (choose file with prompt "Select targets.txt file" of type {"txt"})
EOF
)

if [[ -z "$TARGETS_FILE" ]]; then
  exit 0
fi

# Language selection
LANG_CHOICE=$(osascript <<EOF
choose from list {"RO", "EN", "BOTH"} with prompt "Select language" default items {"RO"}
EOF
)

if [[ -z "$LANG_CHOICE" ]]; then
  exit 0
fi

LANG_CHOICE=$(echo "$LANG_CHOICE" | tr -d '{}"')

# Campaign label
LABEL=$(osascript <<EOF
text returned of (display dialog "Campaign label (optional)" default answer "campaign")
EOF
)

LABEL=$(echo "$LABEL" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')

TS=$(date +"%Y-%m-%d_%H%M")
CAMPAIGN="${LABEL}_${TS}"

# Cleanup?
CLEANUP=$(osascript <<EOF
button returned of (display dialog "Cleanup after run?" buttons {"No","Yes"} default button "Yes")
EOF
)

CLEANUP_FLAG=""
if [[ "$CLEANUP" == "Yes" ]]; then
  CLEANUP_FLAG="--cleanup"
fi

# Run
case "$LANG_CHOICE" in
  RO)
    ./scripts/ship_ro.sh "$TARGETS_FILE" --campaign "$CAMPAIGN" $CLEANUP_FLAG
    ;;
  EN)
    ./scripts/ship_en.sh "$TARGETS_FILE" --campaign "$CAMPAIGN" $CLEANUP_FLAG
    ;;
  BOTH)
    ./scripts/ship_both.sh "$TARGETS_FILE" --campaign "$CAMPAIGN" $CLEANUP_FLAG
    ;;
esac

# Copy to Desktop
DATE_ONLY=$(date +"%Y-%m-%d")
DEST="$HOME/Desktop/PDF ready to ship/$DATE_ONLY/$CAMPAIGN"
mkdir -p "$DEST"

cp -R "deliverables/out/$CAMPAIGN" "$DEST/"
cp "deliverables/out/$CAMPAIGN.zip" "$DEST/"

open "$DEST"

