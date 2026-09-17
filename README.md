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

Do **not** run `terraform apply` on a laptop. The brief requires GitHub Actions.

## How to clone and run

### 1. Repository

```bash
git clone <this-repo>
cd <this-repo>
```

Create a GitHub repo (private is fine) and push `main`.

### 2. GitHub secrets and variables

**Secrets** (Settings → Secrets and variables → Actions):

| Secret | Used by | Purpose |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | `bootstrap.yml` only | Challenge IAM user. Never used after OIDC exists. |
| `AWS_SECRET_ACCESS_KEY` | `bootstrap.yml` only | Same. |
| `GHCR_TOKEN` (optional) | `deploy.yml` | PAT with `read:packages` if GHCR images stay private. |

Do **not** commit the Keeper/CSV access-key file. `*.csv` is gitignored.

**Variables**:

| Variable | When | Purpose |
| --- | --- | --- |
| `AWS_ACCOUNT_ID` | after bootstrap | Account ID for `arn:aws:iam::<id>:role/sentinel-gha` |

Optional GitHub Environments (auto-created on first run): `bootstrap`, `aws`. Add a required reviewer on `aws` if you want a human gate before apply.

### 3. Bootstrap (once)

Actions → **bootstrap** → Run workflow.

This uses the IAM user to create:

- S3 bucket `sentinel-tfstate-<account>-us-east-2` (versioned, encrypted, public access blocked)
- DynamoDB table `sentinel-tfstate-lock`
- OIDC provider `token.actions.githubusercontent.com` (skip if it already exists: set the input to `false`)
- Role **`sentinel-gha`**, assumable only from this repo’s `main` ref and the `aws` / `bootstrap` environments

Copy `AWS_ACCOUNT_ID` from the job log into repository variables.

If `iam:CreateOpenIDConnectProvider` is denied, stop. That is a guardrail, not something to bypass. In production you would ask the platform team to create the provider (account-wide, once) and pass `create_oidc_provider=false` plus the existing ARN.

### 4. Deploy

Push to `main` (or run **deploy**). Stages:

1. **validate-terraform** — `terraform fmt -check`, `tflint`, `terraform validate`
2. **plan** — OIDC assume `sentinel-gha`, `terraform plan -out=tfplan`
3. **apply** — applies that saved plan only
4. **validate-k8s** — kubeconform + `kubectl apply --dry-run=client` (kubeval is unmaintained)
5. **build-and-push** — backend + gateway images to GHCR
6. **deploy** — backend internal NLB, then gateway with that NLB as upstream
7. **smoke** — `curl` the public NLB, expect `Hello from backend`

First apply takes 15–25 minutes (two EKS clusters).

## Repository layout

```
bootstrap/                 # OIDC + state backend (IAM user, once)
environments/sentinel/     # Two VPCs, peering, two EKS clusters
modules/
  vpc/
  vpc-peering/
  iam/                     # eks-* roles and sentinel-gha
  eks/
apps/backend|gateway       # Container images
k8s/backend|gateway        # Kubernetes manifests
.github/workflows/         # Staged Actions
```

Terraform is modular on purpose: each module has its own variables/outputs and is reused (the VPC and EKS modules are instantiated twice).

## Networking

| Name | CIDR | Cluster | Nodes | Internet |
| --- | --- | --- | --- | --- |
| `vpc-gateway` | `10.0.0.0/16` | `eks-gateway` | private subnets | NAT + public NLB |
| `vpc-backend` | `10.1.0.0/16` | `eks-backend` | private subnets | NAT only (no public workload) |

Each VPC has **two AZs**, **two private subnets**, **two public subnets**, **one NAT Gateway**.

Public subnets exist even though the brief only names private ones: a NAT Gateway and an internet-facing NLB must sit on a subnet with an internet gateway. EKS nodes and the backend never get public IPs (`map_public_ip_on_launch = false`). There are no public EC2 instances. The default security group in each VPC has no rules.

**Peering** (not Transit Gateway): one connection, routes in public and private tables on both sides, remote VPC DNS resolution enabled. Two VPCs in one account do not need TGW; TGW would add cost and IAM surface for a POC.

Subnet tags so the in-tree AWS cloud provider places NLBs correctly:

- public: `kubernetes.io/role/elb=1`
- private: `kubernetes.io/role/internal-elb=1`
- both: `kubernetes.io/cluster/<cluster>=shared`

## How the proxy talks to the backend

1. `k8s/backend` Service `type: LoadBalancer` with `aws-load-balancer-scheme: internal` creates an **internal NLB** in `vpc-backend`.
2. GitHub Actions waits for that hostname (public DNS that resolves to **private** IPs).
3. `k8s/gateway` nginx gets `BACKEND_HOST=<nlb-dns>`. Nginx resolves via VPC DNS (`10.0.0.2`) and `proxy_pass`es over peering.
4. Packets: gateway pod → private IP of backend NLB → backend nodes (instance targets) → pods.

No hardcoded pod IPs. No public address on the backend.

## Security model

**Security groups** (on the EKS cluster SG, which managed node groups share):

- **Backend:** TCP 80 and NodePort `30000–32767` only from `10.0.0.0/16` (gateway VPC) and `10.1.0.0/16` (NLB health checks). Not `0.0.0.0/0`.
- **Gateway:** same ports from `0.0.0.0/0` because a public NLB preserves client IPs onto instance targets. That is the internet-facing edge.

**NetworkPolicy** (backend namespace, AWS VPC CNI network policy enabled on the `vpc-cni` addon):

- Default deny all ingress in `sentinel-backend`.
- Allow TCP 8080 to `app=backend` only from `10.0.0.0/16` and `10.1.0.0/16`.

NetworkPolicy is defense in depth. Cross-VPC enforcement is the security group; NetworkPolicy cannot see “the other cluster” as a peer, only CIDRs / pods in *this* cluster.

**EKS API:** private endpoint on, public endpoint on (`0.0.0.0/0`) so GitHub-hosted runners can `kubectl`. Restricting that to GitHub’s published CIDRs (or moving to a self-hosted runner in the VPC) is a documented next step.

**IAM:**

- `eks-gateway-cluster` / `eks-gateway-nodes`
- `eks-backend-cluster` / `eks-backend-nodes`
- `sentinel-gha` — OIDC, least privilege for VPC/EKS/ELB plus `iam:*Role` only on `eks-*` and `sentinel-*`

**Pods:** non-root, dropped capabilities, read-only root FS, no service account token.

## CI/CD

```
push main
  ├─ validate-terraform ──────────────────────► plan (OIDC) ► apply (OIDC)
  ├─ validate-k8s ─────────────────────────┐
  └─ build-and-push (GHCR) ────────────────┴─► deploy (OIDC) ► smoke
```

Kubeval is unmaintained; the pipeline uses **kubeconform** plus `kubectl apply --dry-run=client` as required by the brief.

Images: `ghcr.io/<owner>/sentinel-backend:<sha>` and `sentinel-gateway:<sha>`. The workflow tries to mark packages public so EKS nodes can pull without a long-lived PAT. If org policy blocks that, set `GHCR_TOKEN`.

## Cost (3-day window)

| Choice | Why |
| --- | --- |
| 1 NAT per VPC, not per AZ | NAT is the expensive line item; AZ loss is acceptable for a POC |
| `t3.medium`, 1 node per cluster | Fits two small apps; max 2 if you scale |
| NLB, not ALB | L4 is enough for nginx; fewer rules/WAF |
| Log retention 7 days | CloudWatch |
| No TGW, no multi-account | Peering is enough |

Tear down after scoring: run `terraform destroy` from Actions (add a workflow or `workflow_dispatch` input) so NAT/EKS/NLB stop billing.

## Trade-offs forced by three days

- Public EKS API for GitHub-hosted runners instead of private API + in-VPC runners
- In-tree Service NLB instead of AWS Load Balancer Controller + Ingress
- HTTP only (no ACM / TLS / mTLS)
- One NAT per VPC
- GHCR instead of ECR so node IAM does not need extra push roles (nodes already have ECR *read*; GHCR matches the GitHub-centric pipeline). If pulls fail, use `GHCR_TOKEN` rather than widening AWS IAM.
- Bootstrap still uses the challenge **IAM user** once. After that, every plan/apply/deploy is OIDC. There is no way to create `sentinel-gha` via OIDC before the role exists.

## What I would do next

- ACM TLS on the public NLB, then mTLS between gateway and backend
- Restrict EKS public endpoint to GitHub meta CIDRs, then private-only API + self-hosted runners
- AWS Load Balancer Controller, external-dns, Ingress
- GitOps (Argo CD / Flux) instead of `kubectl apply` from CI
- Cluster autoscaler or Karpenter, one node group per AZ
- NAT per AZ or VPC endpoints (ECR, S3, EKS, EC2, logs) to cut NAT
- Control plane + workload observability (Prometheus, Grafana, CloudWatch Container Insights)
- Secrets in AWS Secrets Manager / External Secrets; Vault if the org already runs it
- Service mesh (Istio / Cilium) if east-west policy must be identity-based, not CIDR-based
- Separate AWS accounts per domain with TGW when this leaves POC

## IAM permission failures

If an API is denied (typical: OIDC provider, some `iam:PassRole`, CloudWatch): **do not** create roles outside `eks-` / `sentinel-` and **do not** attach extra unmanaged policies by hand. Record the error, the assumption, and the production fix (platform team grants the missing action on the existing prefixes).
