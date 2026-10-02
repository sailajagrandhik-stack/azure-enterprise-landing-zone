# Azure Enterprise Landing Zone (Terraform)

A layered Terraform build of a secure Azure foundation for a small-to-medium
company, following the Microsoft Cloud Adoption Framework (CAF) landing zone
model, with a GitHub Actions pipeline using OIDC. Each folder is its own Terraform project with its own
state file, and you apply them **in order**.

| Step | Folder | What it builds | Status |
|---|---|---|---|
| 0 | `00-bootstrap` | Storage account that holds Terraform state (run once, local state) | ✅ ready |
| 1 | `01-foundation` | Management group tree + Entra groups + RBAC (identity) | ✅ ready |
| 2 | `02-policy` | Azure Policy assignments at management group level | ✅ ready |
| 3 | `03-management` | Log Analytics, Defender for Cloud, diagnostic settings | next |
| 4 | `04-connectivity` | Hub VNet, Firewall/NAT, DNS, (VPN) | later |
| 5 | `05-landing-zones` | Spoke VNets + subscriptions for apps (corp / online) | later |

> The "landing zone" is not a step at the end — steps 1–5 **together** are the
> landing zone. Step 5 is where the app teams' spaces get created.

## Target management group layout (SMB-sized)

```
Tenant Root Group
└── grandhi                  (your company root — policies go here)
    ├── platform             (one shared subscription for identity/mgmt/connectivity)
    ├── landingzones
    │   ├── corp             (internal apps, private network)
    │   └── online           (internet-facing apps)
    ├── sandbox              (experiments, loose rules)
    └── decommissioned       (subs waiting to be deleted)
```

Big enterprises split `platform` into identity / management / connectivity,
each with its own subscription. For a small company, one platform
subscription is fine and cheaper — you can split later.

## Prerequisites

1. Azure CLI + Terraform (>= 1.6) installed.
2. `az login` as a user who is **Global Administrator** in the tenant.
3. **Elevate access once** so you can manage management groups:
   Entra ID → Properties → "Access management for Azure resources" → **Yes**.
   (Gives you User Access Administrator at the tenant root. Turn it off later.)
4. Your subscription ID: `az account show --query id -o tsv`

## How to build it

Follow **[RUNBOOK.md](RUNBOOK.md)** — the real-company order:

1. Code goes into Git and is reviewed in a pull request **before** anything runs.
2. Step 0 (state storage) is the only thing ever applied from a laptop, once;
   its state is then moved into Azure.
3. Steps 1+ are applied only by the GitHub Actions pipeline: plan on every
   pull request, apply after merge + approval, signed in to Azure with OIDC
   (no stored secrets).

## Cost

Steps 0–2 cost basically nothing (management groups, groups, RBAC and policy
are free; the state storage account is pennies/month). Step 4 is where cost
appears — Azure Firewall is ~$900+/month, so for a lab or dev setup use NAT Gateway or
skip the firewall and just deploy the hub VNet.

## Clean up

Destroy in **reverse** order: 05 → 04 → 03 → 02 → 01 → 00.
