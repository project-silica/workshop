#!/usr/bin/env bash
# A session starts from the last commit, and what that commit says it ran, it ran (AGENTS.md).
# So a tier or a benchmark has nothing new to say until this session has changed something.
#
#   test-gate.sh start   SessionStart: note when the session began; hand the agent the record
#   test-gate.sh check   PreToolUse(Bash): refuse tools/test.sh and tools/bench.sh (bench.sh
#                        --compare excepted: it measures commits, not the working tree) while no
#                        repository is dirty and none has a commit since the session began
#
# The owner runs anything with `! <command>`, which no hook sees.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
repos=("$root" "$root/kernel" "$root/os" "$root/idl")
input=$(cat)
sid=$(jq -r '.session_id // "none"' <<<"$input")
stamp="$root/target/claude-sessions/$sid"

case "${1:-}" in
start)
	mkdir -p "$(dirname "$stamp")"
	[ -e "$stamp" ] || date +%s >"$stamp"
	{
		echo "The record (the tree is as these commits left it; what they say ran, ran):"
		for r in "${repos[@]}"; do
			echo "== $(basename "$r")"
			git -C "$r" log --format='%h %cr %s' -5 2>/dev/null
		done
		echo "== open gaps (os/bench/open.tsv)"
		grep -v '^#' "$root/os/bench/open.tsv" 2>/dev/null | cut -f1-3
		echo "Start by building. tools/test.sh and tools/bench.sh are refused until this session has changed something."
	} | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
	;;
check)
	cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
	grep -Eq '(^|[^[:alnum:]_])tools/(test|bench)\.sh' <<<"$cmd" || exit 0
	grep -Eq 'tools/bench\.sh.*--compare' <<<"$cmd" && exit 0
	mkdir -p "$(dirname "$stamp")"
	[ -e "$stamp" ] || date +%s >"$stamp"
	since=$(cat "$stamp")
	for r in "${repos[@]}"; do
		[ -n "$(git -C "$r" status --porcelain 2>/dev/null)" ] && exit 0
		last=$(git -C "$r" log -1 --format=%ct 2>/dev/null || echo 0)
		[ "${last:-0}" -ge "$since" ] && exit 0
	done
	jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
		permissionDecisionReason: "Nothing has changed since this session began: no repository is dirty and none has a new commit. The last commits say what ran, and it ran; a tier or benchmark on this tree tells you nothing new. Make the change first, then run the one test that exercises it. (bench.sh --compare of commits is allowed. If the owner asked for this run, ask them to run it with `! <command>`.)"}}'
	;;
esac
exit 0
