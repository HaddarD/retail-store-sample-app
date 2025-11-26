# Retail Store Kubernetes Project - Reflections 💭

## The RabbitMQ Saga 🐰😤

This project was smooth sailing... until Phase 4 hit me like a truck.

RabbitMQ refused to install. The Helm chart kept timing out. I tried everything:
- Increased timeout from 10m to 15m to 20m... nope 🕐
- Checked pod logs... nothing useful 📋
- Restarted the whole deployment... still failing 😵

After way too many attempts, I finally discovered the real culprit: **disk space**. 

RabbitMQ requires **20GB minimum** and my EC2 instances only had **8GB**. Classic case of looking for the problem in the wrong place! 🔍

**The fix:**
```bash
# Get volume IDs
MASTER_VOL=$(aws ec2 describe-instances --instance-ids $MASTER_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text)

# Resize to 20GB
aws ec2 modify-volume --volume-id $MASTER_VOL --size 20 --region us-east-1

# Extend the filesystem
ssh -i $KEY_FILE ubuntu@$MASTER_PUBLIC_IP "sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/nvme0n1p1"
```

Lesson learned: when something times out, **check resources first** before adding more time! ⏰

---

## Phase 5 Hiccups 🤏

- **Git push failed** with 2FA enabled → switched from HTTPS to SSH URL
- **ImagePullBackOff errors** → ECR secret (`regcred`) was missing from `retail-store` namespace. Fixed by updating `03-ecr-setup.sh` to create the secret in both namespaces.
- **RabbitMQ stuck at 0/1 again** → This time it was actually running! The readiness probe had `timeoutSeconds` missing (defaults to 1s - too short!). Added `timeoutSeconds: 10` to GitOps repo, ArgoCD auto-synced, fixed! ✅

---

### 💀 The Great Snapshot Catastrophe of November 24th 2025 💀

So there I was, 1 AM, project **DONE**, feeling great... and then:

1. Tried to create a "victory snapshot" 🎉
2. VirtualBox crashed - host disk full 😵
3. Panicked and deleted old snapshot files manually
4. Broke the entire VirtualBox disk chain - ubuntu won't boot 💀
5. Computer kept restarting because - ***my cat was sitting on the power button!*** 😸🤯🤦‍♀️
6. Ran Recuva & many other softwares at 2 AM hoping for data recovery - no luck 😫
7. Spend the next 2 days attempting to restore what I can from the remaining snapshots 😵
8. Eventually Re-installed a new Ubuntu: 😔
   * Reinstalled AWS CLI, git & gitcli, helm, kubectl, and everything else needed...
   * Reconfigured AWS CLI, Git SSH cli, kubectl access and everything else needed...
   * created a new keypair for EC2 and manually added it to the EC2 instances
   * Cloned this repo - Thank God I pushed it a few minutes before the crash 🤗
   * Had to recreate local file - deployment-info.txt - too many missing variables had to be recovered 🪫
   * Had to restore and reconfigure kubectl as well. 😞

**Lessons learned:** 💡
- Always check host disk space BEFORE snapshots 🧐
- VirtualBox snapshots are a CHAIN - don't delete middle links! 🤦‍♀️
- Keep cats away from computers during critical operations 😸
- SSD hard drive is unrecoverable... 😖
- ***Creating scripts is a HUGE time saver when having to restore everything!*** 📝🤓
- I learned a lot of snapshots manipulation tricks, I created a partial chain of the most current snapshots, separated them from the missing links, and attached them to the base, & attached them to my new VM using USB to try and recover as many files as I can... 🛠️💡🧩

---

## GitOps Implementation Experience 🚀

The workflow clicked once I understood it:
1. Push code to **main repo** → GitHub Actions builds images → pushes to ECR
2. GitHub Actions updates **GitOps repo** with new image tags
3. ArgoCD watches GitOps repo → auto-deploys to cluster

No more manual `helm upgrade` commands. Just `git push` and grab coffee. ☕

**What worked well:** Auto-sync, self-healing, visibility in ArgoCD UI, easy rollbacks via `git revert`.

**What was tricky:** Managing two repos, setting up the PAT token, debugging across multiple systems (Actions → GitOps → ArgoCD → pods).

---

## ArgoCD vs Manual Helm ⚖️

| | Manual Helm | ArgoCD GitOps |
|--|-------------|---------------|
| **Deploy** | `helm upgrade...` | `git push` |
| **Rollback** | `helm rollback` | `git revert` |
| **Audit trail** | Hope you remember | Git history |
| **Self-healing** | ❌ None | ✅ Automatic |
| **Setup** | Simple | More complex initially |

**Verdict:** Helm is great for learning and seeing what happens. ArgoCD is great for "set it and forget it" - worth the setup effort! 💯

---

## What I Learned 🎓

### GitOps is Pretty Cool 😎
The idea is simple: **Git = single source of truth**. You don't manually deploy anything. You push to Git, ArgoCD watches, and automatically syncs the cluster. If someone manually changes something in the cluster? ArgoCD reverts it. Magic! ✨

### Claude Projects with Multiple Chats 🤖
This was my first time using Claude with a project knowledge base across multiple chat sessions. Each phase got its own chat, but they all shared context. It felt like having a teammate who actually remembers what we did last week! Pretty fun workflow.

### Automation is Life 🤩
I ended up with scripts for everything:
- `startup.sh` → Start EC2s, update IPs automatically
- `03-ecr-setup.sh` → Refresh ECR credentials (they expire every 12 hours!)
- `99-cleanup.sh` → Nuke everything when done

Daily startup went from 6 commands to just:
```bash
./startup.sh && source deployment-info.txt && ./03-ecr-setup.sh
```

---

## Final Thoughts 💡

Complex project, but honestly? I enjoyed it. Building a full CI/CD pipeline with GitHub Actions pushing to ECR, ArgoCD watching a GitOps repo, and seeing changes auto-deploy to a kubeadm cluster I built from scratch... that's satisfying. 

Would I do it again? Maybe with 20GB disks from the start next time. 😅

## It's been a fun ride! <(^-^<) <(^.^)> (>^-^)>