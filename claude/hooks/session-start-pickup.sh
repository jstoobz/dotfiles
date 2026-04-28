#!/usr/bin/env bash
set -euo pipefail

SESSION_KIT_ROOT="${SESSION_KIT_ROOT:-$HOME/.stoobz}"
MANIFEST="$SESSION_KIT_ROOT/manifest.json"

signals=()

if [[ -f "CONTEXT_FOR_NEXT_SESSION.md" ]]; then
  signals+=("Relay baton found: CONTEXT_FOR_NEXT_SESSION.md")
fi

if [[ -f "TLDR.md" ]]; then
  signals+=("Session summary found: TLDR.md")
fi

if [[ -f "$MANIFEST" ]]; then
  PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  ACTIVE=$(python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    active = [s for s in data.get('sessions', [])
              if s.get('status') == 'active' and s.get('project') == sys.argv[2]]
    for s in active:
        sid = s.get('session_id', s.get('id', '?'))[:8]
        last = s.get('last_activity', '')[:10]
        ret = s.get('return_to', '')
        print(f'  - {sid} (last active: {last}) {ret}')
except Exception:
    pass
" "$MANIFEST" "$PROJECT" 2>/dev/null)
  if [[ -n "$ACTIVE" ]]; then
    signals+=("Active sessions for '$PROJECT':" "$ACTIVE")
  fi
fi

if [[ ${#signals[@]} -gt 0 ]]; then
  echo "session-kit: pickup signals detected"
  for s in "${signals[@]}"; do
    echo "  $s"
  done
  echo ""
  echo "Consider running /pickup to load prior session context."
fi
