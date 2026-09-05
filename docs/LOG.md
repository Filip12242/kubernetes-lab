# Build log

> Written with AI assistance (Claude Code). The failures below are real ones
> hit on this machine, not illustrative examples.

What broke, and why. Kept because the debugging is the part worth remembering —
and because a log of real failures reads better to anyone looking at this repo
than a clean history that pretends none happened.

Format: date, what happened, what actually fixed it.

---

## 2026-09-05 — repo scaffolded

Hyper-V was already installed and `vmms` running, but the account was not in
**Hyper-V Administrators**, so every `Get-VM` returned a permissions error
rather than an empty list. Fix is one `Add-LocalGroupMember` plus a logout —
group membership is only evaluated at logon.

---

## 2026-09-05 - Hyper-V group not found

`Add-LocalGroupMember -Group "Hyper-V Administrators"` failed with
`GroupNotFoundException`. The group exists; this is a **de-DE** Windows install
and it is named `Hyper-V-Administratoren`.

Windows local group names are localized, their **SIDs are not**. Always address
built-in groups by well-known SID in anything that has to survive a locale
change:

    S-1-5-32-544   Administrators / Administratoren
    S-1-5-32-578   Hyper-V Administrators / Hyper-V-Administratoren

`Get-LocalGroup | Where-Object Name -match Hyper` is the fast way to find the
real name on an unfamiliar machine.

---

## 2026-09-05 - ISO download at 0.8 MB/s

`download.rockylinux.org` was serving at **0.82 MB/s**, ~55 min for a 2.6 GB
ISO. Assumed bad local internet. It was not.

The redirector did **not** bounce us to a geo-local mirror - the effective URL
after `-L` was unchanged, so we were pulling from origin the whole time.
Benchmarked three German mirrors with a 20 MB range request while the slow
transfer was still running:

    download.rockylinux.org    0.82 MB/s
    mirror.netcologne.de      10.98 MB/s
    mirror1.hs-esslingen.de   13.17 MB/s
    mirror.23m.com            14.79 MB/s   <- used

18x. Remaining 1.9 GB finished in 120 s.

Two things worth keeping:

- **Benchmark before assuming the bottleneck is yours.** A ranged `curl` with
  `-w %{speed_download}` costs seconds and settles it. Running it in parallel
  with the slow transfer proved the line had headroom to spare.
- **Cross-mirror resume works** when `Content-Length` matches: `curl -C -`
  against the new host kept all 850 MB already on disk. Verified afterwards
  with the published SHA256, which is the only thing that makes that safe:

      d338032cd1cdd41c67139f2f71b4c832c8e4a21943106519db9c7137df7a63d4

---
