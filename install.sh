#!/usr/bin/env bash
#
# install.sh — install (or remove) ood-xfce-session-timer on a compute-node image.
#
# Run as root on the COMPUTE NODE image (the desktop runs inside the Slurm job,
# so everything installs there, not on the OOD portal node).
#
#   sudo ./install.sh                 # install to the default location
#   sudo ./install.sh --skip-packages # install files only (manage packages yourself)
#   sudo ./install.sh --bindir DIR    # install scripts to a custom directory
#   sudo ./install.sh --uninstall     # remove installed files
#
set -euo pipefail

BINDIR=/opt/ood-session-timer/bin
AUTOSTART_DIR=/etc/xdg/autostart
DESKTOP_FILE=ood-session-timer.desktop
PACKAGES=(xfce4-genmon-plugin libnotify xfce4-notifyd)

SKIP_PACKAGES=0
UNINSTALL=0

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bindir)        BINDIR="${2:?--bindir needs a path}"; shift 2 ;;
    --skip-packages) SKIP_PACKAGES=1; shift ;;
    --uninstall)     UNINSTALL=1; shift ;;
    -h|--help)       usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "This script installs to ${BINDIR} and ${AUTOSTART_DIR}; please run as root (sudo)." >&2
  exit 1
fi

# Locate the repo root (the directory containing this script).
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if (( UNINSTALL )); then
  rm -f "${AUTOSTART_DIR}/${DESKTOP_FILE}"
  rm -f "${BINDIR}/ood-add-timer.sh" "${BINDIR}/ood-timeleft-genmon.sh"
  rmdir --ignore-fail-on-non-empty "${BINDIR}" 2>/dev/null || true
  echo "Removed ood-xfce-session-timer. User home dirs are untouched"
  echo "(per-session genmon rc files and \$TMPDIR caches expire on their own)."
  exit 0
fi

# 1. Packages.
if (( SKIP_PACKAGES )); then
  echo "Skipping package installation (--skip-packages)."
elif command -v dnf >/dev/null 2>&1; then
  echo "Installing packages: ${PACKAGES[*]}"
  if ! dnf install -y "${PACKAGES[@]}"; then
    echo "WARNING: package install failed. xfce4-genmon-plugin lives in EPEL —" >&2
    echo "         enable EPEL (dnf install epel-release) and re-run, or use" >&2
    echo "         --skip-packages and install it through your image pipeline." >&2
  fi
else
  echo "WARNING: dnf not found; skipping packages. Ensure these are present:" >&2
  echo "         ${PACKAGES[*]}" >&2
fi

# 2. Scripts (rendered so PRODUCER / Exec match --bindir).
install -Dm755 "${SRC}/bin/ood-add-timer.sh"       "${BINDIR}/ood-add-timer.sh"
install -Dm755 "${SRC}/bin/ood-timeleft-genmon.sh" "${BINDIR}/ood-timeleft-genmon.sh"

if [[ "$BINDIR" != "/opt/ood-session-timer/bin" ]]; then
  sed -i "s#^PRODUCER=.*#PRODUCER=${BINDIR}/ood-timeleft-genmon.sh#" \
    "${BINDIR}/ood-add-timer.sh"
fi

# 3. Autostart entry (Exec rewritten to match --bindir).
install -Dm644 "${SRC}/autostart/${DESKTOP_FILE}" "${AUTOSTART_DIR}/${DESKTOP_FILE}"
sed -i "s#^Exec=.*#Exec=${BINDIR}/ood-add-timer.sh#" \
  "${AUTOSTART_DIR}/${DESKTOP_FILE}"

echo
echo "Installed:"
echo "  ${BINDIR}/ood-timeleft-genmon.sh"
echo "  ${BINDIR}/ood-add-timer.sh"
echo "  ${AUTOSTART_DIR}/${DESKTOP_FILE}"
echo
echo "Next:"
echo "  - Confirm \$SLURM_JOB_ID reaches the Xfce session, or add the"
echo "    examples/bc_desktop-script.sh.erb.snippet line to your app."
echo "  - Verify the panel id: xfconf-query -c xfce4-panel -p /panels"
echo "  - Launch a short desktop session to test."
