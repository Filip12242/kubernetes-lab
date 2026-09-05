# 00 - Host setup (Windows side)

Hyper-V is already installed and the `vmms` service is running on this machine,
so there is no feature install or reboot needed.

## 1. Grant yourself Hyper-V rights (one time)

Your account is not in the Hyper-V administrators group, so every VM command
currently fails with a permissions error. Add yourself once and you never need
UAC for lab work again.

Open PowerShell **as Administrator**:

```powershell
Add-LocalGroupMember -SID "S-1-5-32-578" -Member $env:USERNAME
```

Addressed by **SID**, not by name, deliberately. Windows local group names are
localized: on this de-DE install the group is `Hyper-V-Administratoren`, so
`-Group "Hyper-V Administrators"` fails with `GroupNotFoundException`. The
well-known SID `S-1-5-32-578` is identical on every locale. Same trick applies
to `S-1-5-32-544` (Administrators / Administratoren).

Then **sign out of Windows and back in** — group membership is only read at
logon, so it will not take effect until you do.

Verify afterwards in a normal (non-admin) shell:

```powershell
Get-VM        # should return empty, not a permissions error
```

## 2. Create the lab network

```powershell
& "D:\Projects\Kubernetes cluster\hyperv\New-LabSwitch.ps1"
```

Creates an Internal switch plus a host NAT so the VMs get stable static IPs and
still reach the internet:

| Host / node | IP               |
|-------------|------------------|
| host vNIC   | 192.168.100.1    |
| k8s-cp1     | 192.168.100.11   |
| k8s-w1      | 192.168.100.12   |
| k8s-w2      | 192.168.100.13   |

The Windows **Default Switch** is deliberately not used: it renumbers its subnet
on every host reboot, which breaks a cluster with node IPs in its config.

## 3. Create the VMs

```powershell
& "D:\Projects\Kubernetes cluster\hyperv\New-LabVms.ps1"
```

Three VMs, 2 vCPU / 4 GB / 40 GB each. That is 6 of your 12 logical cores and
12 GB of your 32 GB, leaving plenty for Windows.

## 4. Install Rocky on each node

```powershell
Start-VM k8s-cp1
vmconnect localhost k8s-cp1
```

In the installer set, per node:

- **Hostname** — `k8s-cp1`, `k8s-w1`, `k8s-w2`
- **Network** — static, from the table above; gateway `192.168.100.1`,
  DNS `1.1.1.1`. Remember to flip the interface to **On**.
- **Software selection** — Minimal Install
- **Root password** and a normal user with sudo

Leave **SELinux enforcing**. It will fight you later during the kubeadm phase.
That fight is the single most RHCSA-relevant part of this whole project — the
official Kubernetes docs tell you to set it permissive, and we are not going to.

## Stretch goal

Doing three installs by hand is fine the first time. Doing it a fourth time is
where you should reach for a **kickstart** file — the RHEL-native way to
automate installs, and an RHCSA exam topic in its own right.
