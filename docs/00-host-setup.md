# Host setup (Windows side)

> Written with AI assistance (Claude Code). Every command here was run on this
> machine, and the output recorded is what actually came back — failures
> included.

Notes from getting the lab network and three VMs running on my workstation.
Ryzen 5 5600X, 32 GB RAM, Windows 11, VMs on the D: drive.

## Starting point

Hyper-V turned out to be already installed — `vmms` was running and the `Get-VM`
cmdlets were present. What was missing was permission. Every VM command returned:

    You do not have the required permission to complete this task.

My account wasn't in the Hyper-V administrators group. The obvious fix failed:

```powershell
Add-LocalGroupMember -Group "Hyper-V Administrators" -Member $env:USERNAME
# Add-LocalGroupMember : Group Hyper-V Administrators was not found.
```

This is a de-DE Windows install, where the group is called
`Hyper-V-Administratoren`. Group *names* are localized; their SIDs are not:

```powershell
Add-LocalGroupMember -SID "S-1-5-32-578" -Member $env:USERNAME
```

Then sign out and back in. Membership is only evaluated at logon, so the running
session keeps its old token and `Get-VM` keeps failing — I lost a few minutes
assuming the command hadn't worked when it had.

Taking forward: address built-in groups by well-known SID in anything that should
survive a locale change. `S-1-5-32-544` is Administrators, `S-1-5-32-578` is
Hyper-V Administrators.

## Network design

```
Internet
    |
[ physical NIC ]           <- New-NetNat masquerades 192.168.100.0/24
    |
[ vEthernet (k8s-lab) ]    192.168.100.1  -- host's port, the nodes' gateway
    |
[ k8s-lab switch ]         Internal, layer 2
  .11         .12        .13
k8s-cp1     k8s-w1     k8s-w2
```

I deliberately avoided the Windows Default Switch: it renumbers its subnet on
every host reboot, which would break a cluster with node IPs baked into its
config. An Internal switch plus a host-side NAT gives stable static addresses,
keeps the lab off my home LAN, and still reaches the internet.

Three commands, elevated. `New-VMSwitch` is covered by the Hyper-V group, but
`New-NetIPAddress` and `New-NetNat` are system network changes and want real
admin:

```powershell
New-VMSwitch -Name 'k8s-lab' -SwitchType Internal
New-NetIPAddress -IPAddress 192.168.100.1 -PrefixLength 24 -InterfaceAlias 'vEthernet (k8s-lab)'
New-NetNat -Name 'k8s-lab-nat' -InternalIPInterfaceAddressPrefix 192.168.100.0/24
```

Creating an Internal switch also creates a host NIC named `vEthernet (k8s-lab)` —
that's the host's own port on the switch, and what the second command addresses.

Windows filed the new adapter under the **Public** profile, which blocks
essentially all inbound traffic. I moved it to Private and allowed ping, scoped
to the lab subnet rather than opening it generally:

```powershell
Set-NetConnectionProfile -InterfaceAlias 'vEthernet (k8s-lab)' -NetworkCategory Private
New-NetFirewallRule -DisplayName "k8s-lab ICMPv4 echo in" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -RemoteAddress 192.168.100.0/24 -Action Allow
```

## The VMs

`hyperv/New-LabVms.ps1` builds all three and skips any that already exist.
Choices worth explaining:

- **Generation 2** — UEFI and SCSI. Rocky 9 installs under UEFI and it boots faster.
- **40 GB dynamic VHDX** — a ceiling, not an allocation. The files started at 4 MB
  and sat around 2.9 GB after a minimal install.
- **Static 4 GB RAM, dynamic memory off** — dynamic memory lets Hyper-V balloon RAM
  away from a running guest, and kubelet reads total memory to make scheduling
  decisions. I'd rather it work from a number that doesn't move underneath it.
- **2 vCPU** — kubeadm refuses to initialise a control plane on fewer.
- **Secure Boot off** — Gen 2 defaults to a Microsoft Windows certificate template
  that won't validate Rocky's bootloader. There's a proper fix
  (`-SecureBootTemplate MicrosoftUEFICertificateAuthority`); I disabled it to keep
  one confusing failure mode out of a first build, and may come back to it.
- **Automatic checkpoints off** — they consume disk quietly, and rolling a node back
  to a stale etcd state isn't something I want happening by accident.
- **AutomaticStopAction ShutDown** — clean ACPI shutdown when the host shuts down,
  rather than save-state. A saved VM resumes with a frozen clock that then jumps,
  and etcd is unforgiving about skew between control plane members.

Running the script failed the first time:

    File ... cannot be loaded because running scripts is disabled on this system.

Every execution policy scope was `Undefined`, so it fell back to the Windows
client default of `Restricted`. Fixed at user scope, no admin needed:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

`RemoteSigned` runs local scripts while still blocking downloaded unsigned ones,
which is the behaviour I want to keep. Worth being clear that execution policy
isn't a security boundary — `Get-Content x.ps1 | powershell -` walks straight
past it. It prevents accidents, not attackers.

## Getting the ISO

`download.rockylinux.org` doesn't redirect to a geo-local mirror. I checked the
effective URL after following redirects and it was unchanged, so it had been
serving from origin the whole time at **0.82 MB/s** — about 55 minutes for a
2.6 GB file. I assumed my connection was the problem.

It wasn't. Benchmarking three German mirrors with a 20 MB ranged request, while
the slow transfer was still running and eating bandwidth:

```
download.rockylinux.org    0.82 MB/s
mirror.netcologne.de      10.98 MB/s
mirror1.hs-esslingen.de   13.17 MB/s
mirror.23m.com            14.79 MB/s
```

Eighteen times faster, and the remaining 1.9 GB finished in 120 seconds.
`Content-Length` matched across mirrors, so `curl -C -` resumed onto the fast one
and kept the 850 MB already on disk. Verified afterwards against the published
`CHECKSUM`, which is the only thing that makes a cross-mirror resume safe:

    d338032cd1cdd41c67139f2f71b4c832c8e4a21943106519db9c7137df7a63d4

Mirror I'd use again:

    https://mirror.23m.com/rocky/9/isos/x86_64/Rocky-9-latest-x86_64-minimal.iso

## Installing Rocky

Minimal Install, German keyboard, Europe/Berlin, automatic partitioning, and a
`filip` user with **Make this user administrator** ticked — that puts the account
in `wheel` so Ansible can `become`.

| VM      | Hostname  | IP                |
|---------|-----------|-------------------|
| k8s-cp1 | `k8s-cp1` | 192.168.100.11/24 |
| k8s-w1  | `k8s-w1`  | 192.168.100.12/24 |
| k8s-w2  | `k8s-w2`  | 192.168.100.13/24 |

Gateway `192.168.100.1`, DNS `1.1.1.1`, IPv4 method Manual, interface toggled
**On** — Anaconda leaves it off by default.

The hostname field needs its **Apply** button pressed; typing it isn't enough.
The "Current host name" readout on the right is what actually took. A node
installing as `localhost` would have confused both me and kubeadm later.

**SELinux stays enforcing.** The upstream Kubernetes docs say to set it
permissive. I'd rather work out the correct contexts — that's the part of this
worth learning, and it's RHCSA material anyway.

## Verifying

All three came up reachable from the host:

```
k8s-cp1   192.168.100.11   ping ok   ssh:22 open
k8s-w1    192.168.100.12   ping ok   ssh:22 open
k8s-w2    192.168.100.13   ping ok   ssh:22 open
```

From inside a node, `ping 1.1.1.1` gives 100% packet loss — but `dnf
check-update` pulled 23 MB at 11 MB/s. So NAT, routing and DNS are all fine;
**WinNAT just doesn't translate ICMP**. TCP and UDP carry port numbers to
demultiplex return traffic on, ICMP doesn't, and Windows' NAT doesn't track the
ICMP identifier field instead.

Outbound ping will never work here regardless of configuration, and it doesn't
matter — nothing in Kubernetes needs it. A good reminder that **ping is not a
connectivity test**: it tests one protocol, and that protocol is the one most
likely to be filtered or unsupported somewhere along the path. `curl`, `nc -z`
and `dnf` are the honest tests.

## Still to do

Automating the install with a **kickstart** file. Three by hand was fine, but I'll
be rebuilding nodes during the kubeadm phase, and unattended five-minute
reinstalls would make me considerably more willing to break things on purpose.
Kickstart is an RHCSA topic too, so it's on the list regardless.
