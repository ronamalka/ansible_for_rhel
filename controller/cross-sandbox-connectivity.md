# Cross-sandbox connectivity (4mrmx → jmvv9)

Assessment date: 2026-07-12. Documents whether the **jmvv9** bastion/AAP environment can manage **4mrmx** RHEL nodes. No lab passwords or private keys are stored in this repository.

## Environments

| Role | Host | Bastion user | Node SSH user / key |
|------|------|--------------|---------------------|
| Legacy (4mrmx) | `ansible-1.4mrmx.sandbox3261.opentlc.com` | `student1` | `ec2-user` / `~/.ssh/4mrmxkey.pem` |
| Current (jmvv9) | `bastion.jmvv9.sandbox3400.opentlc.com` | `lab-user` | `ec2-user` / `~/.ssh/jmvv9key.pem` (when nodes exist) |

## Legacy RHEL nodes (reachable from 4mrmx bastion only)

| Host | IP (4mrmx VPC) | SSH from 4mrmx bastion |
|------|----------------|-------------------------|
| node1.example.com | 192.168.0.130 | OK |
| node2.example.com | 192.168.0.28 | OK |
| node3.example.com | 192.168.0.56 | OK |

On the **4mrmx** bastion: DNS resolves `node*.example.com`, ping succeeds, and `ssh -i ~/.ssh/4mrmxkey.pem ec2-user@nodeN.example.com` returns the expected hostnames.

## Can jmvv9 reach legacy RHEL nodes?

**No.** From `bastion.jmvv9` (192.168.0.81/24):

- `node*.example.com` does **not** resolve (no DNS in jmvv9 for those names).
- Ping to 192.168.0.130 / .28 / .56: **100% packet loss**.
- SSH with `jmvv9key.pem` or copied `4mrmxkey.pem` to those IPs: **No route to host** or timeout.

Both sandboxes use overlapping `192.168.0.0/24` address space on separate VPCs; there is no routed path between them. Public bastion hostnames resolve to different public IPs; ICMP between bastions also fails (likely blocked); SSH between bastions works after key exchange (below).

## AAP (jmvv9) ad-hoc ping results

Workshop Inventory id **34**, Credential id **35** (`ec2-user`, workshop SSH key).

| Job | Target | Result |
|-----|--------|--------|
| Ad-hoc #13 | `node1` (`ansible_host`: `node1.example.com`) | UNREACHABLE — Could not resolve hostname |
| Ad-hoc #15 | `node1` (`ansible_host`: `192.168.0.130`) | UNREACHABLE — Connection timed out |

Inventory host **node1** was reverted to `ansible_host: node1.example.com` after the IP test. **Do not** point jmvv9 inventory at 4mrmx private IPs unless nodes are reprovisioned in the jmvv9 VPC or network peering is added.

Credential **35** was **not** changed to `4mrmxkey.pem`; even with the correct key, jmvv9 execution environments cannot reach the legacy VPC.

## SSH keys exchanged between bastions

Copied via local workstation (not committed to Git):

| Location | Added files |
|----------|-------------|
| jmvv9 bastion `~/.ssh/` | `4mrmxkey.pem`, `4mrmxkey.pub` (from 4mrmx) |
| 4mrmx bastion `~/.ssh/` | `jmvv9key.pem`, `jmvv9key.pub` (from jmvv9) |

Cross-bastion admin (key-based):

- **4mrmx → jmvv9:** `ssh -i ~/.ssh/jmvv9key.pem lab-user@bastion.jmvv9.sandbox3400.opentlc.com`
- **jmvv9 → 4mrmx:** `ssh -i ~/.ssh/jmvv9key.pem student1@ansible-1.4mrmx.sandbox3261.opentlc.com` (requires `jmvv9key.pub` in `student1` `~/.ssh/authorized_keys` on 4mrmx)

## Recommendations

1. Run Ansible against legacy nodes from the **4mrmx** bastion or keep that sandbox alive for RHEL targets.
2. For **jmvv9** demos, provision RHEL VMs in the jmvv9 lab (or add DNS/`/etc/hosts` on bastion and EE for in-VPC nodes only).
3. To manage 4mrmx nodes from jmvv9 AAP would require new nodes in jmvv9 or explicit network peering — not available in standard OpenTLC sandboxes.

See also [README.md](../README.md) OpenTLC note on missing `node*.example.com` in jmvv9.
