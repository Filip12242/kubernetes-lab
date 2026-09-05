# Build log

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
