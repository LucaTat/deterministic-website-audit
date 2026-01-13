 #!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

is_repo_root() {
  [ -f "$1/scripts/ship_ro.sh" ] || [ -f "$1/scripts/ship_en.sh" ]
}

REPO_DIR=""
if is_repo_root "$SCRIPT_DIR"; then
  REPO_DIR="$SCRIPT_DIR"
elif is_repo_root "$SCRIPT_DIR/deterministic-website-audit"; then
  REPO_DIR="$SCRIPT_DIR/deterministic-website-audit"
elif is_repo_root "$HOME/Desktop/deterministic-website-audit"; then
  REPO_DIR="$HOME/Desktop/deterministic-website-audit"
else
  REPO_PATH_FILE="$HOME/Library/Application Support/SCOPE/repo_path.txt"
  if [[ -f "$REPO_PATH_FILE" ]]; then
    CANDIDATE="$(cat "$REPO_PATH_FILE")"
    if [[ -n "$CANDIDATE" && -d "$CANDIDATE" ]] \
      && is_repo_root "$CANDIDATE"; then
      REPO_DIR="$CANDIDATE"
    fi
  fi
fi

if [[ -z "$REPO_DIR" ]]; then
  SELECTED_DIR=$(osascript <<'EOF'
try
  set chosenFolder to choose folder with prompt "Selectează folderul deterministic-website-audit" with title "SCOPE"
  POSIX path of chosenFolder
on error number -128
  return ""
end try
EOF
)
  if [[ -z "$SELECTED_DIR" ]]; then
    exit 0
  fi
  mkdir -p "$HOME/Library/Application Support/SCOPE"
  echo "$SELECTED_DIR" > "$REPO_PATH_FILE"
  REPO_DIR="$SELECTED_DIR"
fi

cd "$REPO_DIR"

osascript <<'EOF'
display dialog "Bine ai venit in SCOPE.

Un instrument intern pentru generarea rapida de audituri de website, clare si gata de trimis." with title "SCOPE" buttons {"GO"} default button "GO"
EOF

osascript <<'EOF'
display dialog "Acest tool genereaza un audit de website client-safe, gata de trimis.

Vei introduce una sau mai multe adrese de website, iar la final vei primi PDF-urile pregatite pentru livrare." with title "SCOPE" buttons {"Continue"} default button "Continue"
EOF

LIST_DIR="./deliverables/archive/targets_lists"
mkdir -p "$LIST_DIR"

DIALOG_BIN=""
if command -v dialog >/dev/null 2>&1; then
  DIALOG_BIN="$(command -v dialog)"
elif [[ -x /usr/local/bin/dialog ]]; then
  DIALOG_BIN="/usr/local/bin/dialog"
elif [[ -x /opt/homebrew/bin/dialog ]]; then
  DIALOG_BIN="/opt/homebrew/bin/dialog"
fi

APP_EDITOR="$REPO_DIR/ui/scope_url_editor/SCOPE URL Editor.app"
APP_BIN="$APP_EDITOR/Contents/MacOS/SCOPEUrlEditor"

has_url_editor_app() {
  [ -d "$APP_EDITOR" ] && [ -x "$APP_BIN" ]
}

prompt_urls_ui() {
  local title="$1"
  local message="$2"
  local default_text="$3"

  if [[ -n "$DIALOG_BIN" ]]; then
    local ts_file=""
    local urls_file=""
    ts_file="$(date +"%Y%m%d_%H%M%S")"
    urls_file="/tmp/scope_urls_${ts_file}.txt"
    printf "%s" "$default_text" > "$urls_file"
    if ! "$DIALOG_BIN" --title "$title" --message "$message" \
      --texteditor "$urls_file" --button1text "Save" --button2text "Cancel" \
      --defaultbutton "1" --cancelbutton "2" >/dev/null; then
      echo "CANCELLED"
      return 0
    fi
    cat "$urls_file"
    return 0
  fi

  local ts_file=""
  local urls_file=""
  local urls_action=""
  ts_file="$(date +"%Y%m%d_%H%M%S")"
  urls_file="/tmp/scope_urls_${ts_file}.txt"
  cat > "$urls_file" <<'EOF'
# Lipește URL-urile mai jos (un URL pe linie).
# Salvează fișierul și închide fereastra ca să continui.
#

EOF
  if [[ -n "$default_text" ]]; then
    printf "%s\n" "$default_text" >> "$urls_file"
  fi

  open -a TextEdit "$urls_file"

  urls_action=$(osascript <<EOF
button returned of (display dialog "$message" with title "$title" buttons {"Continue","Cancel"} default button "Continue")
EOF
)
  if [[ "$urls_action" == "Cancel" ]]; then
    echo "CANCELLED"
    return 0
  fi

  cat "$urls_file"
}

open_url_editor_app() {
  local tmpfile="$1"
  open -W "$APP_EDITOR" --args "$tmpfile"
  return $?
}

prompt_urls_via_app() {
  local default_text="$1"
  local ts_file=""
  local tmp_file=""
  ts_file="$(date +"%Y%m%d_%H%M%S")"
  tmp_file="/tmp/scope_urls_${ts_file}.txt"
  printf "%s" "$default_text" > "$tmp_file"
  open_url_editor_app "$tmp_file"
  local status=$?
  if [[ $status -eq 0 ]]; then
    cat "$tmp_file"
  else
    echo "CANCELLED"
  fi
}

MODE=""
TARGETS_FILE=""
while true; do
  MODE_CHOICE=""
  if ! MODE_CHOICE=$(osascript <<'EOF'
try
  set theChoice to button returned of (display dialog "Select list mode:" with title "SCOPE" buttons {"Run","Create","More…"} default button "Run")
  return theChoice
on error number -128
  return "CANCELLED"
end try
EOF
); then
    exit 0
  fi

  if [[ "$MODE_CHOICE" == "CANCELLED" ]]; then
    exit 0
  fi

  if [[ "$MODE_CHOICE" == "More…" ]]; then
    MORE_CHOICE=$(osascript <<'EOF'
try
  set theChoice to button returned of (display dialog "More options:" with title "SCOPE" buttons {"Edit list","Back","Cancel"} default button "Edit list")
  return theChoice
on error number -128
  return "CANCELLED"
end try
EOF
)
    if [[ "$MORE_CHOICE" == "CANCELLED" || "$MORE_CHOICE" == "Cancel" ]]; then
      exit 0
    fi
    if [[ "$MORE_CHOICE" == "Back" ]]; then
      continue
    fi
    MODE_CHOICE="Edit list"
  fi

  if [[ "$MODE_CHOICE" == "Run" ]]; then
    if ! compgen -G "$LIST_DIR"/*.txt > /dev/null; then
      osascript -e 'display alert "No saved lists found. Create a new list first."'
      continue
    fi
    ITEMS=$(printf '"%s",' $(basename -a "$LIST_DIR"/*.txt))
    ITEMS="${ITEMS%,}"
    FIRST_ITEM=$(basename "$(ls "$LIST_DIR"/*.txt | head -n 1)")
    SELECTED=$(osascript -e "choose from list {$ITEMS} with prompt \"Select targets list\" default items {\"$FIRST_ITEM\"}")
    if [[ -z "$SELECTED" ]]; then
      exit 0
    fi
    SELECTED=$(echo "$SELECTED" | tr -d '{}\"')
    TARGETS_FILE="$LIST_DIR/$SELECTED"
    MODE="run"
  elif [[ "$MODE_CHOICE" == "Edit list" ]]; then
    if ! compgen -G "$LIST_DIR"/*.txt > /dev/null; then
      osascript -e 'display alert "No saved lists found. Create a new list first."'
      continue
    fi
    ITEMS=$(printf '"%s",' $(basename -a "$LIST_DIR"/*.txt))
    ITEMS="${ITEMS%,}"
    FIRST_ITEM=$(basename "$(ls "$LIST_DIR"/*.txt | head -n 1)")
    SELECTED=$(osascript -e "choose from list {$ITEMS} with prompt \"Select targets list\" default items {\"$FIRST_ITEM\"}")
    if [[ -z "$SELECTED" ]]; then
      exit 0
    fi
    SELECTED=$(echo "$SELECTED" | tr -d '{}\"')
    TARGETS_FILE="$LIST_DIR/$SELECTED"
    MODE="edit"
  else
    MODE="create"
  fi

  if [[ "$MODE" == "create" ]]; then
# === Create targets list via UI (no nano, no Terminal) ===
RAW_NAME=""
if ! RAW_NAME=$(osascript <<'EOF'
text returned of (display dialog "Introdu numele listei (ex: example.txt):" default answer "example.txt" with title "SCOPE" buttons {"Cancel","OK"} default button "OK")
EOF
); then
  exit 0
fi

LIST_NAME="$(echo "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+//g')"
if [[ -z "$LIST_NAME" ]]; then
  osascript -e 'display alert "Nume invalid. Oprire."'
  exit 0
fi
if [[ "$LIST_NAME" != *.txt ]]; then
  LIST_NAME="${LIST_NAME}.txt"
fi

URLS=""
while [[ -z "$URLS" ]]; do
  if has_url_editor_app; then
    RAW_URLS="$(prompt_urls_via_app "")"
  else
    RAW_URLS="$(prompt_urls_ui "SCOPE" "Lipește URL-urile (un URL pe linie)." "")"
  fi
  if [[ "$RAW_URLS" == "CANCELLED" ]]; then
    exit 0
  fi

  URLS_LIST=()
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue
    if [[ "$line" != http://* && "$line" != https://* ]]; then
      line="https://$line"
    fi
    URLS_LIST+=("$line")
  done <<< "$RAW_URLS"

  if [[ ${#URLS_LIST[@]} -eq 0 ]]; then
    if [[ -n "$DIALOG_BIN" ]]; then
      "$DIALOG_BIN" --title "SCOPE" --message "Nu am găsit niciun URL valid. Te rog încearcă din nou." \
        --button1text "OK" --defaultbutton "1" >/dev/null
    else
      osascript -e 'display dialog "Nu am găsit niciun URL valid. Te rog încearcă din nou." with title "SCOPE" buttons {"OK"} default button "OK"'
    fi
    continue
  fi

  URLS="$(printf "%s\n" "${URLS_LIST[@]}")"
done

TARGETS_FILE="$LIST_DIR/$LIST_NAME"

# Normalize + save
> "$TARGETS_FILE"
while IFS= read -r line; do
  line="$(echo "$line" | xargs)"
  [[ -z "$line" ]] && continue
  if [[ "$line" != http* ]]; then
    line="https://$line"
  fi
  echo "$line" >> "$TARGETS_FILE"
done <<< "$URLS"

COUNT="$(grep -cve '^\s*$' "$TARGETS_FILE" || true)"
if [[ "$COUNT" -le 0 ]]; then
  osascript -e 'display alert "Nu ai introdus niciun URL valid. Oprire."'
  exit 0
fi

osascript -e "display notification \"Saved targets list: $LIST_NAME ($COUNT URLs)\" with title \"SCOPE\""
TARGETS_COUNT="$COUNT"
    break
  fi

  if [[ "$MODE" == "edit" ]]; then
  DEFAULT_TEXT=""
  if [[ -f "$TARGETS_FILE" ]]; then
    DEFAULT_TEXT="$(cat "$TARGETS_FILE")"
  fi

  UPDATED_URLS=""
  RETURN_TO_MENU=""
  while [[ -z "$UPDATED_URLS" ]]; do
    if has_url_editor_app; then
      RAW_URLS="$(prompt_urls_via_app "$DEFAULT_TEXT")"
    else
      RAW_URLS="$(prompt_urls_ui "SCOPE" "Editează lista (un URL pe linie)." "$DEFAULT_TEXT")"
    fi
    if [[ "$RAW_URLS" == "CANCELLED" ]]; then
      RETURN_TO_MENU="1"
      break
    fi

    URLS_LIST=()
    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      line="$(echo "$line" | xargs)"
      [[ -z "$line" ]] && continue
      if [[ "$line" != http://* && "$line" != https://* ]]; then
        line="https://$line"
      fi
      URLS_LIST+=("$line")
    done <<< "$RAW_URLS"

    if [[ ${#URLS_LIST[@]} -eq 0 ]]; then
      if [[ -n "$DIALOG_BIN" ]]; then
        "$DIALOG_BIN" --title "SCOPE" --message "Nu am găsit niciun URL valid. Te rog încearcă din nou." \
          --button1text "OK" --defaultbutton "1" >/dev/null
      else
        osascript -e 'display dialog "Nu am găsit niciun URL valid. Te rog încearcă din nou." with title "SCOPE" buttons {"OK"} default button "OK"'
      fi
      continue
    fi

    DEDUPED=()
    DEDUPED_SET=$'\n'
    for url in "${URLS_LIST[@]}"; do
      case "$DEDUPED_SET" in
        *$'\n'"$url"$'\n'*) continue ;;
      esac
      DEDUPED+=("$url")
      DEDUPED_SET+="$url"$'\n'
    done

    UPDATED_URLS="$(printf "%s\n" "${DEDUPED[@]}")"
  done

  if [[ "$RETURN_TO_MENU" == "1" ]]; then
    MODE=""
    TARGETS_FILE=""
    continue
  fi

  > "$TARGETS_FILE"
  while IFS= read -r line; do
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue
    if [[ "$line" != http* ]]; then
      line="https://$line"
    fi
    echo "$line" >> "$TARGETS_FILE"
  done <<< "$UPDATED_URLS"

  COUNT="$(grep -cve '^\s*$' "$TARGETS_FILE" || true)"
  LIST_FILE_NAME="$(basename "$TARGETS_FILE")"
  osascript -e "display dialog \"List updated: $LIST_FILE_NAME (Total: $COUNT URLs)\" with title \"SCOPE\" buttons {\"OK\"} default button \"OK\""
  TARGETS_COUNT="$COUNT"
  MODE="run"
  break
  fi

  if [[ "$MODE" == "run" ]]; then
    break
  fi
done

if [[ -z "$TARGETS_COUNT" ]]; then
  TARGETS_COUNT="$(grep -cve '^\s*$' "$TARGETS_FILE" || true)"
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

# Campaign label default based on list
LIST_BASENAME="$(basename "$TARGETS_FILE")"
LIST_BASENAME="${LIST_BASENAME%.txt}"
if [[ -z "$LIST_BASENAME" ]]; then
  LIST_BASENAME="campaign"
fi

# Campaign label
LABEL=$(osascript <<EOF
text returned of (display dialog "Campaign label (optional)" default answer "$LIST_BASENAME" with title "SCOPE")
EOF
)

if [[ -z "$LABEL" ]]; then
  exit 0
fi

LABEL=$(echo "$LABEL" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')

TS=$(date +"%Y-%m-%d_%H%M")
CAMPAIGN="${LABEL}_${TS}"

# Cleanup?
CLEANUP=$(osascript <<EOF
button returned of (display dialog "Cleanup after run?" buttons {"No (debug)","Yes (recommended)","Cancel"} default button "Yes (recommended)" with title "SCOPE")
EOF
)

if [[ "$CLEANUP" == "Cancel" ]]; then
  exit 0
fi

CLEANUP_FLAG=""
if [[ "$CLEANUP" == "Yes (recommended)" ]]; then
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

# Copy to Desktop (PDF ready to ship) — bulletproof
DEST_DATE="$(date +%F)"
DEST_BASE="$HOME/Desktop/PDF ready to ship"
DEST_DIR="$DEST_BASE/$DEST_DATE/$CAMPAIGN"

mkdir -p "$DEST_DIR"

# Copy campaign folder (if present)
if [[ -d "deliverables/out/$CAMPAIGN" ]]; then
  cp -R "deliverables/out/$CAMPAIGN" "$DEST_DIR/"
else
  echo "[WARN] campaign folder missing: deliverables/out/$CAMPAIGN"
fi

# Copy ZIP (prefer exact campaign zip, fallback to most recent zip)
ZIP_PATH="deliverables/out/$CAMPAIGN.zip"
if [[ -f "$ZIP_PATH" ]]; then
  cp -v "$ZIP_PATH" "$DEST_DIR/"
else
  LATEST_ZIP="$(ls -t deliverables/out/*.zip 2>/dev/null | head -n 1)"
  if [[ -n "$LATEST_ZIP" && -f "$LATEST_ZIP" ]]; then
    echo "[INFO] Using latest ZIP fallback: $LATEST_ZIP"
    cp -v "$LATEST_ZIP" "$DEST_DIR/"
  else
    echo "[WARN] No ZIP found in deliverables/out/"
  fi
fi

ZIP_TO_REVEAL=""
if [[ -f "$DEST_DIR/$CAMPAIGN.zip" ]]; then
  ZIP_TO_REVEAL="$DEST_DIR/$CAMPAIGN.zip"
else
  ZIP_TO_REVEAL="$(ls -t "$DEST_DIR"/*.zip 2>/dev/null | head -n 1)"
fi

PDF_SINGLE=""
PDFS_ALL=()
for PDF_DIR in "$DEST_DIR" "$DEST_DIR/$CAMPAIGN"; do
  if [[ -d "$PDF_DIR" ]]; then
    while IFS= read -r pdf; do
      PDFS_ALL+=("$pdf")
    done < <(ls "$PDF_DIR"/*.pdf 2>/dev/null)
  fi
done
if [[ ${#PDFS_ALL[@]} -eq 1 ]]; then
  PDF_SINGLE="${PDFS_ALL[0]}"
fi

BUTTONS="\"Open folder\",\"Reveal ZIP\",\"OK\""
if [[ -n "$PDF_SINGLE" ]]; then
  BUTTONS="\"Open folder\",\"Reveal PDF\",\"OK\""
fi

FINAL_MESSAGE="Campaign: $CAMPAIGN
Saved to: $DEST_DIR"

FINAL_ACTION=$(osascript <<EOF
try
  set theChoice to button returned of (display dialog "$FINAL_MESSAGE" with title "SCOPE" buttons {$BUTTONS} default button "Open folder")
  return theChoice
on error number -128
  return "CANCELLED"
end try
EOF
)
if [[ -z "$FINAL_ACTION" || "$FINAL_ACTION" == "CANCELLED" ]]; then
  exit 0
fi

case "$FINAL_ACTION" in
  "Open folder")
    if [[ -d "$DEST_DIR" ]]; then
      open "$DEST_DIR"
    else
      echo "[WARN] Destination folder missing: $DEST_DIR"
      open "$DEST_BASE"
    fi
    ;;
  "Reveal ZIP")
    if [[ -n "$ZIP_TO_REVEAL" && -f "$ZIP_TO_REVEAL" ]]; then
      open -R "$ZIP_TO_REVEAL"
    else
      open "$DEST_DIR"
    fi
    ;;
  "Reveal PDF")
    if [[ -n "$PDF_SINGLE" && -f "$PDF_SINGLE" ]]; then
      open -R "$PDF_SINGLE"
    else
      open "$DEST_DIR"
    fi
    ;;
  "OK")
    :
    ;;
esac
