# Rapyd Sentinel — Split Architecture

Proof of concept for **Rapyd Sentinel**: two isolated AWS VPCs, two EKS clusters, private cross-VPC traffic, a public gateway proxy, and a GitHub Actions pipeline that is the **only** Terraform apply path.

Region is **`us-east-2`**. IAM roles are created only with prefixes **`eks-`** (cluster/node) and **`sentinel-`** (GitHub OIDC deploy role).

```
Internet
   │
   ▼
Public NLB  ──►  eks-gateway (nginx proxy)
                      │
                      │  VPC peering (private IPv4)
                      ▼
Internal NLB ──►  eks-backend  ("Hello from backend")
```

Do **not** run `terraform apply` on a laptop. The brief mandates GitHub Actions.

---

## How to clone and run

### 1. Repository

```bash
git clone https://github.com/yuvalavni/rapyd-sentinel
cd rapyd-sentinel
```

### 2. GitHub secrets and variables

**Secrets** (Settings → Secrets and variables → Actions):

| Secret | Used by | Purpose |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | `bootstrap.yml` only | Challenge IAM user — used once, never again after OIDC is created |
| `AWS_SECRET_ACCESS_KEY` | `bootstrap.yml` only | Same |

Do **not** commit the Keeper/CSV access-key file — `*.csv` is gitignored.

**Variables**:

| Variable | Set when | Purpose |
| --- | --- | --- |
| `AWS_ACCOUNT_ID` | After bootstrap | Account ID for `arn:aws:iam::<id>:role/sentinel-gha-ci3` |

### 3. Bootstrap (once)

Actions → **bootstrap** → Run workflow.

This uses the IAM user to:
- Create S3 bucket `sentinel-tfstate-<account>-us-east-2` (versioned, AES256, public access blocked)
- Look up the account's existing GitHub OIDC provider
- Create IAM role **`sentinel-gha-ci3`** — assumable only from this repo via OIDC

Copy `AWS_ACCOUNT_ID` from the job log into repository variables.

**Guardrails encountered and how they were handled:**

| Denied action | Response |
| --- | --- |
| `dynamodb:CreateTable` | No DynamoDB lock table. State locking via GitHub Actions `concurrency` group instead. |
| `iam:CreateOpenIDConnectProvider` | Look up the existing account-wide GitHub OIDC provider; only create the `sentinel-*` role. |
| `iam:TagRole` | Role created without tags. |
| `iam:UpdateAssumeRolePolicy` | Cannot update existing trust policy. Created a new role (`sentinel-gha-ci3`) with the correct trust policy from day one. |
| `iam:UpdateRoleDescription` | `lifecycle { ignore_changes = [description, tags] }` on EKS IAM roles. |

### 4. Deploy

Push to `main` (or trigger **deploy** via `workflow_dispatch`). Stages run in this order:

```
push main
  ├─ validate-terraform ──────────────────────► plan (OIDC) ► apply (OIDC)
  ├─ validate-k8s ─────────────────────────┐
  └─ build-and-push (GHCR) ────────────────┴─► deploy (OIDC) ► smoke
```

1. **validate-terraform** — `terraform fmt -check`, `tflint`, `terraform validate`
2. **plan** — OIDC assume `sentinel-gha-ci3`, `terraform plan -out=tfplan`
3. **apply** — applies the saved plan artifact only (no re-plan)
4. **validate-k8s** — kubeconform + `kubectl apply --dry-run=client`
5. **build-and-push** — backend + gateway images pushed to GHCR tagged with git SHA
6. **deploy** — backend internal NLB created first; gateway configured with that NLB as upstream
7. **smoke** — `curl` the public NLB, expect `Hello from backend`

First apply takes ~15 minutes (two EKS clusters). Subsequent pushes are ~5 minutes (no-op plan + deploy).

### 5. Tear down

Actions → **destroy** → type `destroy` → Run workflow.

The destroy workflow:
1. Deletes both Kubernetes namespaces so the in-tree controller removes the NLBs from AWS (prevents orphaned resources that would block VPC deletion)
2. Waits for the NLBs to disappear from AWS
3. Runs `terraform destroy`

---

## Repository layout

```
bootstrap/                 # One-time: S3 state, OIDC provider lookup, sentinel-gha-ci3 role
environments/sentinel/     # Main environment: two VPCs, peering, two EKS clusters
  terraform.tfvars         # ← single file to change per environment
modules/
  vpc/                     # VPC, subnets, IGW, NAT, route tables, default SG lock
  vpc-peering/             # VPC peering connection + routes on both sides
  iam/                     # eks-* cluster/node roles + sentinel-* OIDC deploy role
  eks/                     # EKS cluster, managed node group, addons, access entries, SG rules
apps/backend/              # Python "Hello from backend" web server + Dockerfile
apps/gateway/              # NGINX reverse proxy + Dockerfile
k8s/backend/               # Deployment, internal NLB Service, NetworkPolicy
k8s/gateway/               # Deployment, public NLB Service
scripts/                   # render-manifests.sh, deploy-apps.sh, smoke.sh
.github/workflows/
  bootstrap.yml            # IAM user — runs once
  deploy.yml               # OIDC — runs on every push to main
  destroy.yml              # OIDC — manual, requires typing "destroy"
```

Terraform is modular: each module has its own `variables.tf` / `outputs.tf` and is reused without duplication (VPC and EKS modules are each instantiated twice).

To spin up a second environment: copy `environments/sentinel/terraform.tfvars`, change the values, point the backend at a different S3 key.

---

## Networking

| Name | CIDR | Cluster | Nodes | Internet |
| --- | --- | --- | --- | --- |
| `vpc-gateway` | `10.0.0.0/16` | `eks-gateway` | private subnets only | NAT + public NLB |
| `vpc-backend` | `10.1.0.0/16` | `eks-backend` | private subnets only | NAT only — no public workload |

Each VPC has **two AZs**, **two private subnets**, **two public subnets**, **one NAT Gateway**.

Public subnets exist even though the brief names only private ones: a NAT Gateway and an internet-facing NLB must attach to a subnet with an internet gateway. EKS nodes and the backend never get public IPs (`map_public_ip_on_launch = false`). The default security group in each VPC is locked (no ingress, no egress).

**Peering** (not Transit Gateway — TGW adds cost and IAM surface for a single-account POC): one connection, routes in both public and private tables on both sides, remote VPC DNS resolution enabled.

Subnet tags for the in-tree AWS cloud provider to discover NLB placement:

- public: `kubernetes.io/role/elb=1`
- private: `kubernetes.io/role/internal-elb=1`
- both: `kubernetes.io/cluster/<cluster>=shared`

## How the proxy talks to the backend

1. `k8s/backend` `Service` (`type: LoadBalancer`, `scheme: internal`) → in-tree controller creates an **internal NLB** in `vpc-backend` private subnets.
2. GitHub Actions waits for that NLB hostname (public DNS that resolves to **private** IPs in `10.1.x.x`).
3. `k8s/gateway` NGINX gets `BACKEND_HOST=<nlb-dns>`. NGINX resolves via VPC DNS (`10.0.0.2`) and `proxy_pass`es over VPC peering.
4. Packet path: gateway pod → private IP of backend NLB → backend nodes (instance targets) → pods.

No hardcoded pod IPs. No public address on the backend at any layer.

---

## Security model

### Security groups
Applied to the EKS cluster security group, which managed node groups share:

- **Backend:** TCP 80 and NodePort `30000–32767` allowed **only** from `10.0.0.0/16` (gateway VPC) and `10.1.0.0/16` (NLB health checks). `0.0.0.0/0` is never present.
- **Gateway:** same ports from `0.0.0.0/0` — required because a public NLB with instance targets preserves client source IPs onto the nodes; there is no way to restrict this to the NLB's own IPs.

### NetworkPolicy
AWS VPC CNI network policy is enabled on the `vpc-cni` addon (`enableNetworkPolicy: true`):

- Default deny-all ingress in `sentinel-backend` namespace.
- Allow TCP 8080 to `app=backend` pods only from `10.0.0.0/16` (gateway VPC) and `10.1.0.0/16` (NLB health checks from within the same VPC).

NetworkPolicy is defense in depth inside the cluster. The primary cross-VPC boundary is enforced by the security group — NetworkPolicy cannot identify "the other cluster" as a peer, only CIDRs.

### IAM — least privilege

The `sentinel-gha-ci3` deploy role policy is split into named statements, each scoped as tightly as AWS supports:

| Statement | Actions | Resources |
| --- | --- | --- |
| `EKSRead` | `ListClusters`, `DescribeAddonVersions` | `*` (AWS doesn't support resource-level for these) |
| `EKSMutate` | Cluster CRUD + `AccessKubernetesApi` | `arn:aws:eks:*:ACCOUNT:cluster/eks-*` |
| `EKSNodegroups` | Nodegroup CRUD | `cluster/eks-*` + `nodegroup/eks-*` |
| `EKSAddons` | Addon CRUD | `cluster/eks-*` + `addon/eks-*` |
| `EKSAccessEntries` | Access entry CRUD | `cluster/eks-*` + `access-entry/eks-*` |
| `IAMRolesPrefixGuardrail` | Role/policy CRUD + `PassRole` | `role/eks-*` + `role/sentinel-*` only |
| `IAMServiceLinkedEKS` | `CreateServiceLinkedRole` | Specific EKS/ELB service role ARNs |
| `EC2NetworkingAndNodes` | VPC/subnet/SG/peering actions | `*` (EC2 Describe doesn't support resource-level) |
| `LoadBalancing` | 27 explicit ELB actions | `*` (ELB doesn't support resource-level) |
| `AutoScaling` | 19 explicit actions | `*` |
| `TerraformStateS3` | `GetObject`, `PutObject`, `DeleteObject`, `ListBucket` | Specific state bucket ARN only |

A Terraform `precondition` in the IAM module enforces the `eks-` / `sentinel-` prefix at plan time — the pipeline refuses to proceed if a misconfigured role name is passed.

### Pod security
Both workloads: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities: drop: [ALL]`, `automountServiceAccountToken: false`, `seccompProfile: RuntimeDefault`.

### EKS API
Private endpoint enabled, public endpoint enabled for GitHub-hosted runners. Restricting to GitHub's published CIDRs (or using a self-hosted runner inside the VPC) is a documented next step.

---

## CI/CD pipeline

```
push main
  ├─ validate-terraform ──────────────────────► plan (OIDC) ► apply (OIDC)
  ├─ validate-k8s ─────────────────────────┐
  └─ build-and-push (GHCR) ────────────────┴─► deploy (OIDC) ► smoke
```

- **No long-lived AWS credentials in deploy.yml** — every AWS step assumes `sentinel-gha-ci3` via GitHub OIDC (`sts:AssumeRoleWithWebIdentity`).
- **Saved plan artifact** — the plan produced in `plan` is the exact file applied in `apply`. No re-plan, no drift.
- **Concurrency lock** — `group: sentinel-us-east-2, cancel-in-progress: false` prevents concurrent applies. New runs queue behind the in-progress one.
- Kubeval is unmaintained; the pipeline uses **kubeconform** (current standard) and `kubectl apply --dry-run=client`.
- Images: `ghcr.io/<owner>/sentinel-backend:<git-sha>` and `sentinel-gateway:<git-sha>`.

---

## Cost (3-day window)

| Choice | Reason |
| --- | --- |
| 1 NAT per VPC, not per AZ | NAT is the dominant line item; AZ loss acceptable for a POC |
| `t3.medium`, 1 node per cluster | Fits both workloads; trivial to scale via `terraform.tfvars` |
| NLB not ALB | L4 is sufficient for NGINX proxy; no WAF/listener rules needed |
| Log retention 7 days | Minimises CloudWatch cost |
| VPC Peering not Transit Gateway | One account, two VPCs — TGW adds cost with no benefit here |

Tear down: run the **destroy** workflow. NAT Gateways and NLBs are the primary ongoing cost.

---

## Trade-offs forced by the three-day limit

- Public EKS API endpoint for GitHub-hosted runners (vs. private API + in-VPC self-hosted runner)
- In-tree Service NLB instead of AWS Load Balancer Controller + Ingress
- HTTP only — no ACM / TLS / mTLS between gateway and backend
- One NAT per VPC (not per AZ — single point of AZ failure)
- GHCR instead of ECR — avoids adding ECR push permissions to the node role; matches the GitHub-centric pipeline
- Bootstrap still uses the challenge IAM user once to create the OIDC role; after that every action is OIDC

---

## What I would do next

- **TLS everywhere** — ACM cert on the public NLB, mTLS between gateway and backend via a service mesh
- **Private EKS API** — restrict public endpoint to GitHub published CIDRs, then move to private-only + self-hosted runner in the VPC
- **AWS Load Balancer Controller** — annotation-driven Ingress, path-based routing, WAF integration
- **GitOps** — Argo CD or Flux instead of `kubectl apply` from CI; declarative desired state, drift detection
- **Karpenter** — node autoscaling with bin-packing; spot instances for non-critical workloads
- **VPC endpoints** — ECR, S3, EKS, EC2, logs endpoints eliminate NAT traffic for AWS API calls
- **Observability** — Prometheus + Grafana for workloads, CloudWatch Container Insights for control plane; distributed tracing
- **Secrets management** — AWS Secrets Manager + External Secrets Operator; Vault if org already runs it
- **Service mesh** (Istio / Cilium) — if east-west policy must be identity-based rather than CIDR-based
- **Multi-account** — separate AWS accounts per domain (gateway, backend) with Transit Gateway when this graduates from POC
