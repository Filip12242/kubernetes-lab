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

## 2026-09-07 - containerd kept the wrong cgroup driver

The task that generates `/etc/containerd/config.toml` was guarded with
`creates:` pointed at that same path. It never ran, and never reported
anything wrong — Ansible printed `ok` on every play.

The containerd.io RPM ships a stub at exactly that path. The file already
existed, so `creates:` did its job and skipped, leaving the packaged default
in place: `SystemdCgroup = false`. The kubelet on Rocky uses the systemd
driver. Two cgroup managers disagreeing on one machine is the kind of
mismatch that surfaces much later as pods that will not start, not as an
error at install time.

`creates:` tests whether a **path exists**, not whether its **contents are
right**. For a config file that ships with defaults, existence proves
nothing. Replaced it with a content check:

    - name: check whether the containerd config has been generated
      ansible.builtin.command: grep -q SystemdCgroup /etc/containerd/config.toml
      register: containerd_config_generated
      changed_when: false
      failed_when: false

    - name: create containerd config
      ansible.builtin.shell: containerd config default > /etc/containerd/config.toml
      when: containerd_config_generated.rc != 0

`failed_when: false` because a non-zero grep is the expected signal here, not
a failure. `changed_when: false` because a task that only looks at something
should never report `changed`.

`creates:` is not the problem, misreading it is. On the kubeadm join step
`creates: /etc/kubernetes/kubelet.conf` is exactly right — nothing but
kubeadm writes that file, so its existence really does mean the work is done.

---

## 2026-09-07 - ansible.posix 1.6 needs a newer ansible-core

The collection install pulled 1.6.2, which requires ansible-core 2.15. Rocky
9 ships 2.14, and that is the version the distro supports, so the fix is
pinning the collection rather than chasing a newer core:

    - name: ansible.posix
      version: "<1.6"

Same shape as the community.general pin from 09-05. Distro Ansible moves
slower than Galaxy does, so anything in `requirements.yml` without a ceiling
is a rebuild that breaks months from now for no reason connected to what
changed.

---

## 2026-09-08 - pods could not talk across nodes, and every port was open

First symptom was name resolution. A busybox pod could not reach the Service
by name:

    wget: bad address 'web'

That reads like a DNS problem, but CoreDNS is itself a pod, and it was
running on the other worker. "DNS is broken" and "the pod network is broken"
produce the identical message, so the symptom was useless. Dropped to IPs.

Everything that should have existed, existed. The Service had a ClusterIP
(`10.97.33.145`), six nginx pods were Running, split three on w1 and three on
w2, and the endpoint list held all six. Three curls from cp1 to the ClusterIP
returned `000` — not a refusal, no response at all.

Checked the obvious thing on cp1 and on w1:

    8472/udp open in firewalld        yes, both nodes
    10.244.x.0/24 via flannel.1       yes, both nodes

which is the part worth keeping. Ports correct, routes correct, traffic still
dead. That rules out an entire category of cause instead of one item in it.

VXLAN arrives on 8472/udp and is handled by **INPUT**, and that half was
working the whole time. The packet is then decapsulated, and the inner
pod-to-pod packet is **routed** — `flannel.1` to `cni0`. Routed traffic is
filtered by **FORWARD**, a separate chain with separate rules, and firewalld's
default zone drops it. No port can fix this, because by that point the packet
is not arriving at the host, it is passing through it.

The fix is a zone, not a port. Bind the pod and service networks as trusted
sources:

    - name: trust kube zone in firewalld
      ansible.posix.firewalld:
        source: "{{ item }}"
        zone: trusted
        permanent: true
        state: enabled
        immediate: true
      loop:
        - "{{ pod_cidr }}"
        - "{{ service_cidr }}"

Three `200`s immediately after.

The lesson is not about flannel. A green playbook and three Ready nodes prove
nothing about the data plane. Control plane traffic is the kubelet dialing
the API server on 6443, an ordinary inbound connection that was never
affected — so the cluster reported perfect health for as long as this lasted.

---
