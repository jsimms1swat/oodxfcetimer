#!/usr/bin/env bash
#
# ood-add-timer.sh — add an Xfce panel countdown for an OOD desktop session and
# fire walltime warnings. Runs from /etc/xdg/autostart in every Xfce session;
# no-ops outside a Slurm interactive job. Idempotent across reconnects.
#
# Usage: ood-add-timer.sh [--restart]
#   --restart   force `xfce4-panel --restart` after adding the plugin (only if
#               your build doesn't live-add when the id appears in plugin-ids).

set -uo pipefail

# ---------- config ----------
PLUGIN_ID=1000                                   # high id, avoids default collisions
PANEL=panel-1                                    # verify: xfconf-query -c xfce4-panel -p /panels
CHANNEL=xfce4-panel
PRODUCER=/opt/ood/firebird/bin/ood-timeleft-genmon.sh
UPDATE_MS=30000
FONT="Monospace 10"
WARN_AT=(1800 600 300 60)                        # notify thresholds (seconds)
ENABLE_NOTIFY=1                                  # 0 disables popups
# ----------------------------

RESTART=0; [[ "${1:-}" == "--restart" ]] && RESTART=1

JOBID="${SLURM_JOB_ID:-}"
[[ -z "$JOBID" && -r "$HOME/.ood-session-job" ]] && JOBID=$(<"$HOME/.ood-session-job")
[[ -z "$JOBID" ]] && exit 0                       # not an OOD desktop job → do nothing

cache="${TMPDIR:-/tmp}/ood_endtime_${JOBID}"
if [[ ! -s "$cache" ]]; then
  end=$(scontrol show job "$JOBID" 2>/dev/null | grep -oP 'EndTime=\K\S+')
  [[ -n "$end" && "$end" != "Unknown" ]] && date -d "$end" +%s > "$cache"
fi

# idempotent xfconf setter: set if present, else create
xfq() {
  xfconf-query -c "$CHANNEL" -p "$1" -t "$2" -s "$3" 2>/dev/null \
    || xfconf-query -c "$CHANNEL" -p "$1" -n -t "$2" -s "$3" 2>/dev/null || true
}

# 1. register plugin type
xfq "/plugins/plugin-${PLUGIN_ID}" string genmon

# 2a. settings via xfconf (genmon >= 4.2.0)
xfq "/plugins/plugin-${PLUGIN_ID}/command"       string "$PRODUCER"
xfq "/plugins/plugin-${PLUGIN_ID}/update-period" int    "$UPDATE_MS"
xfq "/plugins/plugin-${PLUGIN_ID}/use-label"     bool   false
xfq "/plugins/plugin-${PLUGIN_ID}/font"          string "$FONT"

# 2b. settings via rc file (genmon < 4.2.0)
rc="${HOME}/.config/xfce4/panel/genmon-${PLUGIN_ID}.rc"
mkdir -p "$(dirname "$rc")"
cat > "$rc" <<EOF
Command=${PRODUCER}
UpdatePeriod=${UPDATE_MS}
UseLabel=false
Font=${FONT}
SingleRow=true
EOF

# 3. append to panel item list (guard against double-add)
mapfile -t ids < <(xfconf-query -c "$CHANNEL" -p "/panels/${PANEL}/plugin-ids" 2>/dev/null | grep -E '^[0-9]+$')
if ! printf '%s\n' "${ids[@]:-}" | grep -qx "$PLUGIN_ID"; then
  args=(); for i in "${ids[@]:-}"; do [[ -n "$i" ]] && args+=(-t int -s "$i"); done
  args+=(-t int -s "$PLUGIN_ID")
  xfconf-query -c "$CHANNEL" -p "/panels/${PANEL}/plugin-ids" -n "${args[@]}" 2>/dev/null || true
fi

# 4. optional forced restart
if (( RESTART )); then xfce4-panel --restart >/dev/null 2>&1 || true; fi

# 5. background walltime warnings
if (( ENABLE_NOTIFY )) && [[ -s "$cache" ]]; then
  ( for sec in "${WARN_AT[@]}"; do
      while [[ -s "$cache" ]] && (( $(<"$cache") - $(date +%s) > sec )); do sleep 20; done
      notify-send -u critical "OOD session ending" \
        "~$((sec/60)) min of walltime left — save your work." 2>/dev/null || true
    done ) &
fi

exit 0
