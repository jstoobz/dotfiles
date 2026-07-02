#!/usr/bin/env bash
# PreToolUse/Bash guard: deny a small, curated set of unambiguously
# catastrophic commands. Runs in EVERY permission mode, so it backstops
# --dangerously-skip-permissions, where permissions.deny rules do not apply.
#
# Design bias: err toward ALLOW. It is an ACCIDENT backstop, not adversarial
# defense (the operator has a shell either way). Two consequences:
#   - Quoted substrings are stripped before matching, so trigger phrases inside
#     commit messages / echo / grep args ("fix reset --hard bug") do not block.
#   - A catastrophic target must directly follow the rm invocation, so compound
#     lines like `rm -rf _build && cd .` stay safe.
# No `set -e`: a grep "no match" (exit 1) is normal and must not abort.

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# Normalize whitespace, strip '..'/".." quoted runs, re-collapse, pad with spaces
# so leading/trailing tokens match the " token " patterns below.
n=" $(printf '%s' "$cmd" | tr '\n\t' '  ' | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" | tr -s ' ') "

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Catastrophic rm targets (bare root/home/cwd/wildcard), directly after rm flags.
T='(/|/\*|~|~/|\$HOME|\$HOME/|\.|\./|\.\.|\.\./|\*)'
RM="(^| )rm +(-[a-zA-Z]+ +)*(-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*|-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*|-[rR] +-[fF]|-[fF] +-[rR]) +${T}( |\$)"
printf '%s' "$n" | grep -Eq "$RM" \
  && deny "Catastrophic rm blocked: recursive/force delete of root, home, cwd, or wildcard. Run it yourself outside Claude if truly intended."

# Fork bomb.
printf '%s' "$n" | grep -Eq ':\(\) *\{ *:\|: *& *\} *;? *:' && deny "Fork bomb blocked."

# Filesystem / raw-device destruction.
printf '%s' "$n" | grep -Eq ' (mkfs[. ]|dd [^|;&]*of=/dev/|> */dev/(sd|nvme|disk)|shred [^|;&]*/dev/)' \
  && deny "Disk/device write blocked."

# Git history/worktree destruction (bypass-proof mirror of the deny rules).
printf '%s' "$n" | grep -Eq ' git [^|;&]*push [^|;&]*(-f|--force)( |$)' && deny "git force-push blocked."
printf '%s' "$n" | grep -Eq ' git [^|;&]*reset [^|;&]*--hard' && deny "git reset --hard blocked."
printf '%s' "$n" | grep -Eq ' git [^|;&]*clean [^|;&]*-[a-zA-Z]*f' && deny "git clean -f blocked."

exit 0
