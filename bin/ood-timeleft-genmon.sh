#!/usr/bin/env bash
# GenMon producer: remaining walltime for the current OOD desktop Slurm job.

JOBID="${SLURM_JOB_ID:-}"
[[ -z "$JOBID" && -r "$HOME/.ood-session-job" ]] && JOBID=$(<"$HOME/.ood-session-job")
[[ -z "$JOBID" ]] && { echo "<txt></txt>"; exit 0; }   # if not in a job, render nothing

cache="${TMPDIR:-/tmp}/ood_endtime_${JOBID}"
if [[ ! -s "$cache" ]]; then
  end=$(scontrol show job "$JOBID" 2>/dev/null | grep -oP 'EndTime=\K\S+')
  [[ -n "$end" && "$end" != "Unknown" ]] && date -d "$end" +%s > "$cache"
fi
[[ -s "$cache" ]] || { echo "<txt> --:--</txt>"; exit 0; }

left=$(( $(<"$cache") - $(date +%s) ))
(( left < 0 )) && left=0
clock=$(printf '%d:%02d:%02d' $((left/3600)) $(((left%3600)/60)) $((left%60)))

if   (( left <= 300 ));  then color="#e01b24"; w="bold"
elif (( left <= 1800 )); then color="#f5c211"; w="normal"
else                          color="#33d17a"; w="normal"
fi

echo "<txt><span foreground='${color}' weight='${w}'>  ${clock}</span></txt>"
echo "<tool>Session ends $(date -d "@$(<"$cache")" '+%a %H:%M'). Save your work first.</tool>"
