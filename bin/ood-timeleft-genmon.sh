#!/usr/bin/env bash
# ood-timeleft-genmon.sh — GenMon producer: remaining walltime for the current
# OOD desktop Slurm job. Renders nothing when not inside an interactive job.
#
# Part of ood-xfce-session-timer. See README for installation.

# Resolve the job id: prefer the environment, fall back to the file written by
# the bc_desktop template (see examples/bc_desktop-script.sh.erb.snippet).
JOBID="${SLURM_JOB_ID:-}"
[[ -z "$JOBID" && -r "$HOME/.ood-session-job" ]] && JOBID=$(<"$HOME/.ood-session-job")
[[ -z "$JOBID" ]] && { echo "<txt></txt>"; exit 0; }

# Resolve the job EndTime ONCE and cache it, so we don't poll slurmctld every
# cycle. Subsequent renders are pure local date math.
cache="${TMPDIR:-/tmp}/ood_endtime_${JOBID}"
if [[ ! -s "$cache" ]]; then
  end=$(scontrol show job "$JOBID" 2>/dev/null | grep -oP 'EndTime=\K\S+')
  [[ -n "$end" && "$end" != "Unknown" ]] && date -d "$end" +%s > "$cache"
fi
[[ -s "$cache" ]] || { echo "<txt>--:--  </txt>"; exit 0; }

left=$(( $(<"$cache") - $(date +%s) ))
(( left < 0 )) && left=0
clock=$(printf '%d:%02d:%02d' $((left/3600)) $(((left%3600)/60)) $((left%60)))

# Color thresholds. The leading/trailing spaces inside the span pad the panel item so it
# doesn't sit flush against the next button.
if   (( left <= 300 ));  then color="#e01b24"; w="bold"    # < 5 min
elif (( left <= 1800 )); then color="#f5c211"; w="normal"  # < 30 min
else                          color="#33d17a"; w="normal"
fi

echo "<txt><span foreground='${color}' weight='${w}'>  ${clock}  </span></txt>"
echo "<tool>Session ends $(date -d "@$(<"$cache")" '+%a %H:%M'). Save your work first.</tool>"
