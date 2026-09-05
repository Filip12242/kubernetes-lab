# Kubernetes lab cluster

A three-node Kubernetes cluster built from scratch on Hyper-V, on Rocky Linux,
configured with Ansible.

The Kubernetes part is the goal. The Rocky-plus-Ansible part is the reason it is
built this way: the same work doubles as hands-on practice for the operations
skills (systemd, journald, Ansible, an enterprise distro, SELinux) that are
worth more, sooner, than Kubernetes itself.

## Layout

```
docs/       build notes, in order
hyperv/     Windows-side provisioning (switch, NAT, VMs)
ansible/    node configuration
```

## Phases

**Phase A — the machines.** Three Rocky VMs on a stable NAT network, fully
configured by Ansible, with Prometheus and Grafana on top. Independently
worthwhile: it is most of the RHCSA hands-on material with a project attached.

**Phase B — the cluster.** containerd, kubeadm, a CNI, joining the workers.

**Phase C — the interesting part.** CNI internals, NetworkPolicy, Pod Security
Admission, RBAC. The networking and security depth this was started for.

## Topology

| Node    | IP             | Role          | vCPU | RAM  |
|---------|----------------|---------------|------|------|
| k8s-cp1 | 192.168.100.11 | control plane | 2    | 4 GB |
| k8s-w1  | 192.168.100.12 | worker        | 2    | 4 GB |
| k8s-w2  | 192.168.100.13 | worker        | 2    | 4 GB |

Host vNIC is `192.168.100.1`, which is also the nodes' gateway.

## Start here

[docs/00-host-setup.md](docs/00-host-setup.md)

## Ground rules

- **SELinux stays enforcing.** The upstream Kubernetes docs say to set it
  permissive. Working out the right contexts instead is the most transferable
  thing in this repo.
- **Nothing gets configured by hand twice.** If a change needs making on all
  three nodes, it goes in a playbook. That constraint is the entire point.
- **Failures get written down.** See [docs/LOG.md](docs/LOG.md).
