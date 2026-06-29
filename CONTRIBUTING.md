# Contributing

Thanks for your interest in improving **ood-xfce-session-timer**. This is a
small project aimed at HPC sites running Open OnDemand, so the bar for
contributing is low and practical experience from your own deployment is the
most valuable thing you can bring.

## Ways to contribute

- **Bug fixes** — especially edge cases in job-id resolution, xfconf/rc handling
  across genmon versions, or panel quirks on different Xfce builds.
- **Portability** — adaptations for other interactive desktop environments
  (MATE, GNOME Flashback) or other schedulers (PBS, LSF). The current design
  assumes Xfce + GenMon + Slurm; a clean way to support alternatives is welcome.
- **Documentation** — clarifications, additional troubleshooting cases, or notes
  on how it behaves on a specific OnDemand version.

## Reporting an issue

Because the behavior depends heavily on the local stack, please include:

- OS and version (e.g. Rocky Linux 9.4)
- Open OnDemand version and the desktop app (`bc_desktop` or a custom app)
- `xfce4-genmon-plugin` version (`rpm -q xfce4-genmon-plugin`)
- Slurm version
- What you expected vs. what you saw (a screenshot of the panel helps for
  rendering issues)
- Relevant output from a test session — for example
  `xfconf-query -c xfce4-panel -p /panels` and whether `$SLURM_JOB_ID` is
  visible inside the session

## Testing changes

There is no substitute for a real session, so please test against an actual OOD
Xfce desktop before opening a PR:

- Request a **short** session (e.g. 30 minutes) so you can watch the countdown
  cross the amber (30 min) and red (5 min) thresholds and confirm the
  notifications fire.
- Test a **reconnect** (close the browser tab and reconnect from *My Interactive
  Sessions*) to confirm the injector doesn't add a second panel item — it must
  stay idempotent.
- If you touched job-id handling, test both paths: with `$SLURM_JOB_ID` present
  in the environment, and with it absent but `~/.ood-session-job` written.

Please also run [ShellCheck](https://www.shellcheck.net/) on any changed shell
script and keep it clean:

```bash
shellcheck bin/*.sh install.sh
```

## Style and design conventions

- Bash, targeting the version shipped on RHEL 9 family. Keep it readable;
  comment anything non-obvious (xfconf array handling, the rc-vs-xfconf split).
- **Keep the producer cheap.** It runs every interval on every desktop, so it
  must not call the scheduler after the first render — resolve `EndTime` once
  and read from the cache. Changes that reintroduce per-tick `scontrol`/`squeue`
  calls will be asked to revise; on a busy cluster that adds up.
- Keep everything **idempotent** and **no-op outside a job**, so the scripts are
  safe to run in any session.
- Don't write to user home directories beyond the existing per-session genmon
  `rc` file, and keep caches in `$TMPDIR`.

## Pull requests

1. Fork and create a topic branch.
2. Make the change, run ShellCheck, and test in a live session as above.
3. In the PR description, say what you tested on (OS / OOD / genmon / Slurm
   versions) and what behavior you verified.

Small, focused PRs are easier to review than large ones — splitting unrelated
changes is appreciated.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE) that covers this project.
