# LinkedIn post

Attach `assets/linkedin-post.png` (1080×1350). Put the repo link in the **first comment**, not the post body: LinkedIn tends to show posts with external links to fewer people.

---

My Ubuntu laptop wouldn't boot on its newest kernel.

So I booted it on an older kernel, gave Claude SSH access, and let it fix the problem while I watched.

What it found in about 10 minutes:
VirtualBox's kernel module couldn't compile for Linux 7.0 → the kernel install stopped halfway → no initrd → no boot.

What it did next:
✅ Fixed it, kept my VMs, rebooted to prove it
✅ Upgraded 24.04 → Ubuntu 26.04.1 LTS (~2,300 packages)
✅ Set the machine up for DevOps: VirtualBox, Docker, Kubernetes tools, Terraform, Ansible…

The interesting part wasn't the fix. It was giving an AI agent root on a real machine without regretting it.

The playbook I'd follow again:

1️⃣ Boot an older kernel. Keep a way back.
2️⃣ SSH with a key, from the LAN only. No passwords in chat.
3️⃣ Temporary sudo that's checked by visudo and expires on its own (my hand-typed rule had a typo).
4️⃣ Read-only diagnosis first. No changes until the root cause is clear.
5️⃣ Reversible steps: remove, don't purge. Rename, don't delete. Back up /etc.
6️⃣ Long jobs under systemd-run. SSH really did drop mid-upgrade, and the upgrade kept going.
7️⃣ Reboot, verify, revoke access.

I wrote it all up as an open repo: the scripts, the prompts I used, and every mistake we hit (a PPA Python that survived the upgrade, a truncated kubectl, geo-blocked repos…).

Link in the first comment 👇

#DevOps #Linux #Ubuntu #AI #ClaudeCode #SysAdmin #Automation

---

**First comment:**

Playbook + scripts: https://github.com/YOUR_GITHUB_USERNAME/claude-ssh-rescue-playbook
