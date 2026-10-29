#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CELLAR="${MOLE_CELLAR:-/opt/homebrew/Cellar/mole/1.53.0}"
PAYLOAD="$ROOT/Resources/Mole/arm64"

if [[ ! -x "$CELLAR/bin/mole" || ! -d "$CELLAR/libexec/bin" || ! -d "$CELLAR/libexec/lib" ]]; then
  echo "Local Mole 1.53.0 Homebrew installation not found at $CELLAR" >&2
  exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "The locally installed Mole bottle targets Apple Silicon; Intel payload is unavailable." >&2
  exit 1
fi

rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
ditto "$CELLAR/libexec" "$PAYLOAD"
cp "$CELLAR/LICENSE" "$PAYLOAD/LICENSE"
cp "$CELLAR/README.md" "$PAYLOAD/README.md"
install -m 755 "$CELLAR/bin/mole" "$PAYLOAD/mole"
python3 - "$PAYLOAD/mole" "$PAYLOAD/lib/clean/dev.sh" <<'PY'
import pathlib, re, sys
entry = pathlib.Path(sys.argv[1])
text = entry.read_text()
text = text.replace("SCRIPT_DIR='/opt/homebrew/Cellar/mole/1.53.0/libexec'", 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"')
entry.write_text(text)

module = pathlib.Path(sys.argv[2])
text = module.read_text()
function_anchor = 'clean_tool_cache() {\n    local description="$1"\n    local cache_path="$2"\n    shift 2\n'
guard = '''
    if [[ -z "$cache_path" ]]; then
        echo -e "  ${GRAY}${ICON_WARNING}${NC} $description · stopped (cache path unavailable)"
        note_activity
        return 0
    fi

'''
if 'cache path unavailable' not in text:
    if function_anchor not in text:
        raise SystemExit('Mole clean_tool_cache contract changed; refusing to patch')
    text = text.replace(function_anchor, function_anchor + guard, 1)
text, comment_count = re.subn(r'^#\s+\$2\s*=.*$', '#   $2 = required cache path checked against the whitelist', text, count=1, flags=re.MULTILINE)
if comment_count != 1:
    raise SystemExit('Mole clean_tool_cache argument documentation could not be verified')
if 'cache path unavailable' not in text:
    raise SystemExit('Mole empty-cache-path guard could not be verified')
module.write_text(text)

logger = module.parents[1] / 'core' / 'log.sh'
log_text = logger.read_text()
log_text = log_text.replace(
    'readonly LOG_FILE="${HOME}/Library/Logs/mole/mole.log"',
    'readonly LOG_FILE="${MOLE_LOG_FILE:-${HOME}/Library/Logs/mole/mole.log}"',
    1,
)
log_text = log_text.replace(
    'readonly DEBUG_LOG_FILE="${HOME}/Library/Logs/mole/mole_debug_session.log"',
    'readonly DEBUG_LOG_FILE="${MOLE_DEBUG_LOG_FILE:-${HOME}/Library/Logs/mole/mole_debug_session.log}"',
    1,
)
log_text = log_text.replace(
    'readonly OPERATIONS_LOG_FILE="${HOME}/Library/Logs/mole/operations.log"',
    'readonly OPERATIONS_LOG_FILE="${MOLE_OPERATIONS_LOG:-${HOME}/Library/Logs/mole/operations.log}"',
    1,
)
if 'MOLE_OPERATIONS_LOG:-' not in log_text:
    raise SystemExit('Mole operation logger contract changed; refusing to patch')
logger.write_text(log_text)

clean = module.parents[1].parent / 'bin' / 'clean.sh'
clean_text = clean.read_text()
category_helper = '''mole_clean_category_for_section() {
    case "$1" in
        "System") printf system ;;
        "User essentials") printf essentials ;;
        "App caches") printf app_caches ;;
        "Browsers") printf browsers ;;
        "Cloud & Office") printf cloud_office ;;
        "Developer tools") printf developer ;;
        "Apps & utilities") printf apps ;;
        "Virtualization") printf virtualization ;;
        "Application Support") printf support ;;
        "App leftovers") printf leftovers ;;
        "Apple Silicon") printf apple_silicon ;;
        "Device backups & firmware") printf backups ;;
        "Time Machine") printf time_machine ;;
        "Large files") printf large_files ;;
        "Project artifacts") printf projects ;;
        "External volume") printf external ;;
        *) return 1 ;;
    esac
}

mole_clean_category_selected() {
    local requested="${MOLE_CLEAN_CATEGORY:-all}"
    [[ "$requested" == "all" ]] && return 0
    [[ "$(mole_clean_category_for_section "$1")" == "$requested" ]]
}

'''
start_anchor = 'start_section() {\n    TRACK_SECTION=1\n    SECTION_ACTIVITY=0\n    CURRENT_SECTION="$1"\n'
if 'mole_clean_category_for_section() {' not in clean_text:
    if start_anchor not in clean_text:
        raise SystemExit('Mole clean section contract changed; refusing category integration')
    clean_text = clean_text.replace(start_anchor, category_helper + start_anchor + '''    if ! mole_clean_category_selected "$CURRENT_SECTION"; then
        TRACK_SECTION=0
        SECTION_ACTIVITY=0
        return 0
    fi
'''.replace('+', ''), 1)

step_anchor = '''    _run_cleanup_step() {
        local pending_clean_cancel="${MOLE_CLEAN_CANCEL_STATUS:-0}"
'''.replace('+', '')
step_guard = '''    _run_cleanup_step() {
        mole_clean_category_selected "${CURRENT_SECTION:-}" || return 0
        local pending_clean_cancel="${MOLE_CLEAN_CANCEL_STATUS:-0}"
'''
if step_guard not in clean_text:
    if step_anchor not in clean_text:
        raise SystemExit('Mole cleanup step contract changed; refusing category integration')
    clean_text = clean_text.replace(step_anchor, step_guard, 1)

cloud_anchor = '''            # ===== 5. Cloud & Office =====
            start_section "Cloud & Office"
'''.replace('+', '')
if 'if mole_clean_category_selected "Cloud & Office"; then' not in clean_text:
    if cloud_anchor not in clean_text:
        raise SystemExit('Mole cloud cleanup section changed; refusing category integration')
    clean_text = clean_text.replace(cloud_anchor, cloud_anchor + '            if mole_clean_category_selected "Cloud & Office"; then\n', 1)
    cloud_end = '''            end_section

            # ===== 6. Developer tools'''
    if cloud_end not in clean_text:
        raise SystemExit('Mole cloud cleanup boundary changed; refusing category integration')
    clean_text = clean_text.replace(cloud_end, '''            end_section
            fi

            # ===== 6. Developer tools'''.replace('+', ''), 1)

apple_anchor = '            _run_cleanup_step clean_apple_silicon_caches || return $?\n'
if 'start_section "Apple Silicon"' not in clean_text:
    if apple_anchor not in clean_text:
        raise SystemExit('Mole Apple Silicon cleanup section changed; refusing category integration')
    clean_text = clean_text.replace(apple_anchor, '            start_section "Apple Silicon"\n            _run_cleanup_step clean_apple_silicon_caches || return $?\n            end_section\n', 1)

clean.write_text(clean_text)
PY
chmod 755 "$PAYLOAD/mole" "$PAYLOAD/bin"/*.sh "$PAYLOAD/bin/analyze-go" "$PAYLOAD/bin/status-go"
cat > "$ROOT/Resources/Mole/BUNDLED_VERSION.txt" <<'EOF'
Mole 1.53.0 (Homebrew bottle installed locally)
License: GPL-3.0-or-later
Architecture: Apple Silicon arm64
EOF
echo "Prepared locally installed Mole 1.53.0 for Apple Silicon."
