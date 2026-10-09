#!/usr/bin/env bash
# Symlink the proj CLI and the project-coordinator skill into place and link the
# herdr notification plugin. Re-running is safe.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bin_dir="${BIN_DIR:-$HOME/.local/bin}"
skills_dir="${OMP_SKILLS_DIR:-$HOME/.omp/agent/skills}" # omp's native user skill root

for dep in herdr jq git flock notify-send; do
	command -v "$dep" >/dev/null || echo "warning: $dep not found on PATH" >&2
done

mkdir -p "$bin_dir" "$skills_dir"
ln -sfn "$here/bin/proj" "$bin_dir/proj"
ln -sfn "$here/skills/project-coordinator" "$skills_dir/project-coordinator"
echo "proj   -> $bin_dir/proj"
echo "skill  -> $skills_dir/project-coordinator"

if command -v herdr >/dev/null; then
	if herdr plugin list --json | jq -e '[.. | .plugin_id? // empty] | index("omp-session-orchestrator.notify")' >/dev/null; then
		echo "plugin -> omp-session-orchestrator.notify (already linked)"
	else
		herdr plugin link "$here/herdr-plugin" >/dev/null
		echo "plugin -> omp-session-orchestrator.notify (linked)"
	fi
	cat <<'EOF'

To let the plugin replace herdr's own notifications (they can't be filtered per pane),
set in ~/.config/herdr/config.toml, then run `herdr server reload-config`:

  [ui.toast]
  delivery = "off"

  [ui.sound]
  enabled = false
EOF
fi

case ":$PATH:" in *":$bin_dir:"*) ;; *) echo "warning: $bin_dir is not on PATH" >&2 ;; esac
