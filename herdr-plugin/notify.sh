#!/usr/bin/env bash
# herdr event handler for pane.agent_status_changed. Replaces herdr's built-in
# toast (set [ui.toast] delivery = "off" and [ui.sound] enabled = false).
#
#   proj workspace (`proj:<project>`) -> notify only on `blocked`: an ask/approval
#       dialog only the user can answer. Threads report `done` to the coordinator,
#       and the coordinator asks the user through the `ask` tool when it needs a
#       decision, so finished turns there never need the user.
#   any other pane -> notify on `blocked` and `done`, like herdr's built-in toast.
#
# Each notification plays herdr's own sound (sounds/done.mp3, sounds/request.mp3),
# the same one herdr plays with [ui.sound] on.
#
# herdr injects HERDR_PLUGIN_EVENT_JSON ({"data":{"pane_id","agent_status","workspace_id",...}}),
# HERDR_BIN_PATH and HERDR_PLUGIN_CONFIG_DIR. Optional settings go in
# $HERDR_PLUGIN_CONFIG_DIR/config.env (`herdr plugin config-dir omp-session-orchestrator.notify`):
#   PROJ_NOTIFY_SOUND=0   no sounds
#   PROJ_NOTIFY_DEBUG=1   log every decision to stderr (`herdr plugin log list`)
set -euo pipefail

config=${HERDR_PLUGIN_CONFIG_DIR:-}/config.env
# shellcheck source=/dev/null
[[ -n ${HERDR_PLUGIN_CONFIG_DIR:-} && -f $config ]] && . "$config"
herdr_bin=${HERDR_BIN_PATH:-herdr}
event=${HERDR_PLUGIN_EVENT_JSON:-'{}'}
sound_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sounds

decide() {
	[[ ${PROJ_NOTIFY_DEBUG:-0} == 1 ]] && printf '[proj-notify] pane=%s status=%s -> %s\n' "${pane:-?}" "${status:-?}" "$1" >&2
	return 0
}

pane=$(jq -r '.data.pane_id // empty' <<<"$event")
status=$(jq -r '.data.agent_status // empty' <<<"$event")
[[ -n $pane && -n $status ]] || { decide "drop: event without pane or status"; exit 0; }
[[ $status == blocked || $status == done ]] || { decide "drop: status"; exit 0; }

pane_json=$("$herdr_bin" pane get "$pane" 2>/dev/null) || { decide "drop: pane gone"; exit 0; }
ws=$(jq -r '.result.pane.workspace_id // empty' <<<"$pane_json")
tab=$(jq -r '.result.pane.tab_id // empty' <<<"$pane_json")
ws_json=$("$herdr_bin" workspace get "$ws" 2>/dev/null) || ws_json='{}'
ws_label=$(jq -r '.result.workspace.label // empty' <<<"$ws_json")

# The user is looking at it: herdr's built-in toast stays quiet here as well.
if [[ $(jq -r '.result.workspace.focused // false' <<<"$ws_json") == true &&
	$(jq -r '.result.workspace.active_tab_id // empty' <<<"$ws_json") == "$tab" ]]; then
	decide "drop: focused"
	exit 0
fi

agent_name=$("$herdr_bin" agent get "$pane" 2>/dev/null | jq -r '.result.agent.name // empty') || agent_name=""
tab_label=$("$herdr_bin" tab get "$tab" 2>/dev/null | jq -r '.result.tab.label // empty') || tab_label=$tab
title=$(jq -r '.result.pane.terminal_title_stripped // empty' <<<"$pane_json")

if [[ $ws_label == proj:* ]]; then
	project=${ws_label#proj:}
	[[ $status == blocked ]] || { decide "drop: proj $project $agent_name done"; exit 0; }
	who=${agent_name#"$project"-}
	summary="[$project/${who:-$tab_label}] needs you"
	body="${title:+$title. }Waiting on a dialog in its tab (herdr agent focus $pane)."
else
	summary="${ws_label:-$ws} / ${tab_label:-$tab}: $([[ $status == blocked ]] && echo "needs input" || echo "done")"
	body=$title
fi

urgency=normal sound=done
[[ $status == blocked ]] && urgency=critical sound=request
notify-send --app-name=herdr --urgency="$urgency" "$summary" "$body"
if [[ ${PROJ_NOTIFY_SOUND:-1} == 1 && -f $sound_dir/$sound.mp3 ]]; then
	# Same player order as herdr's src/sound.rs on Linux.
	for player in paplay pw-play "ffplay -nodisp -autoexit -loglevel quiet" "mpg123 -q" "mpv --really-quiet"; do
		command -v "${player%% *}" >/dev/null || continue
		setsid -f $player "$sound_dir/$sound.mp3" </dev/null >/dev/null 2>&1
		break
	done
fi
decide "notify: $summary"
