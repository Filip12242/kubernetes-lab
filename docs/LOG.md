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
