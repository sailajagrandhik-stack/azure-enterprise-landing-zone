# Runbook — building the platform the way a real company does

The order matters. **Code goes into Git before anything runs.** Your laptop
applies exactly one thing, once (Step 0). Everything after that goes through
pull requests and the pipeline.

```
Part 0   Clean up any earlier test setup
Part 1   Decisions (before any code runs)
Part 2   Tools on your laptop
Part 3   Create the GitHub repo
Part 4   First commit (repo skeleton)          ← the only direct push to main
Part 5   Protect the main branch
Part 6   PR #1  bootstrap code                  ← reviewed BEFORE it runs
Part 7   Run Step 0 from your laptop            ← the only laptop apply, ever
Part 8   PR #2  move bootstrap state into Azure
Part 9   Connect GitHub to Azure (OIDC)
Part 10  PR #3  pipeline + Step 1 (foundation)  ← pipeline applies from here on
Part 11  Lock it down
Part 12  PR #4  Step 2 (policy)
```

---

## Part 0 — Clean up an earlier test setup (skip on a brand-new tenant)

Only safe while **nothing else uses the state storage** (no Step 1+ applied).

```powershell
cd C:\CODE\azure-enterprise-landing-zone\00-bootstrap

# 1. Remove the delete lock first (otherwise Azure refuses to delete the storage)
terraform destroy -target="azurerm_management_lock.tfstate"

# 2. Remove everything else
terraform destroy

# 3. Confirm it's gone (should print: false)
az group exists -n rg-grandhi-tfstate

# 4. Remove local leftovers (keep terraform.tfvars)
Remove-Item -Recurse -Force .terraform, terraform.tfstate*, .terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item ..\backend.hcl -ErrorAction SilentlyContinue
```

If step 2 says `ScopeLocked`, wait a minute and run `terraform destroy` again.

---

## Part 1 — Decisions (agree on these before any code runs)

Changing these later is painful. At a company, settle them with your manager.

| Decision | This repo uses | Where it's set |
|---|---|---|
| Company prefix | `grandhi` | `prefix` in tfvars / `TF_PREFIX` |
| Regions | `southcentralus` (primary), `centralus` (backup) | `location`, `allowed_locations` |
| Required tags | `owner`, `environment` | `required_tags` (Step 2) |
| Naming pattern | `<type>-<prefix>-<purpose>` e.g. `rg-grandhi-tfstate` | in the code |
| Management groups | root → platform, landingzones (corp, online), sandbox, decommissioned | Step 1 |
| Who approves production | you (later: a second engineer) | GitHub environment `production` |
| Network IP plan | decided before Step 4 | Step 4 |

---

## Part 2 — Tools on your laptop

```powershell
winget install --id Git.Git -e          # then close and reopen PowerShell
git --version
git config --global user.name  "Sailaja Grandhi"
git config --global user.email "<the email on your GitHub account>"

az version          # Azure CLI
terraform version   # note this number — the pipeline should use the same one
```

---

## Part 3 — Create the GitHub repo

github.com → **+** → **New repository**
- Name: `azure-enterprise-landing-zone`
- **Public** · do **not** add a README, .gitignore or license

> On GitHub's free plan, approval gates and branch rules only work on public
> repos. No secrets live in this code (IDs go in GitHub Secrets, state lives in
> Azure), so public is safe. At a company: **private** repo in the company's
> GitHub organization.

---

## Part 4 — First commit: the repo skeleton

Only the basics. This is the **one and only** direct push to `main`.

```powershell
cd C:\CODE\azure-enterprise-landing-zone
git init -b main
git add .gitignore README.md RUNBOOK.md
git status                     # only those 3 files
git commit -m "Repo skeleton: README, runbook, gitignore"
git remote add origin https://github.com/<your-username>/azure-enterprise-landing-zone.git
git push -u origin main        # a browser window opens to sign in to GitHub
```

---

## Part 5 — Protect the main branch

Repo → **Settings → Rules → Rulesets → New ruleset → New branch ruleset**
- Name `protect-main` · Enforcement **Active** · Target: **Include default branch**
- ✅ Restrict deletions · ✅ Block force pushes
- ✅ Require a pull request before merging (required approvals: **0** while you're solo)
- **Create**

From now on, every change goes through a pull request — including yours.

---

## Part 6 — PR #1: the bootstrap code (reviewed before it runs)

```powershell
git switch -c feature/00-bootstrap
git add 00-bootstrap scripts
git status                     # NO terraform.tfvars, NO .tfstate listed
git commit -m "Step 0: Terraform state storage + OIDC setup script"
git push -u origin feature/00-bootstrap
```

On GitHub: **Compare & pull request** → **Create pull request** →
open **Files changed** and read the code like a reviewer would →
**Merge pull request** → **Delete branch**.

```powershell
git switch main
git pull
```

---

## Part 7 — Run Step 0 from your laptop (the only laptop apply)

Run it from `main`, so what runs is exactly what was reviewed.

```powershell
az login
az account show -o table       # right subscription?

cd 00-bootstrap
copy terraform.tfvars.example terraform.tfvars   # only if you don't have one
# check terraform.tfvars: subscription_id, prefix = "grandhi"
terraform init
terraform plan
terraform apply

terraform output -raw backend_config | Out-File -Encoding ascii ..\backend.hcl
Get-Content ..\backend.hcl
```

---

## Part 8 — PR #2: move the bootstrap's state into Azure

Right now Step 0's state is a file on your laptop. If the laptop dies, it's
gone. Move it into the storage account it just created.

```powershell
git switch -c feature/bootstrap-remote-state

# Add a backend block (values come from backend.hcl)
@"
# Added AFTER the first apply: the storage didn't exist before that.
terraform {
  backend "azurerm" {
    key = "00-bootstrap.tfstate"
  }
}
"@ | Out-File -Encoding ascii backend.tf

terraform init -migrate-state -backend-config="..\backend.hcl"
# Answer "yes" to "Do you want to copy existing state to the new backend?"

terraform state list      # should list the resources → state is now in Azure
terraform plan            # should say: No changes

Remove-Item terraform.tfstate, terraform.tfstate.backup -ErrorAction SilentlyContinue

cd ..
git add 00-bootstrap/backend.tf 00-bootstrap/.terraform.lock.hcl
git commit -m "Step 0: store bootstrap state in Azure"
git push -u origin feature/bootstrap-remote-state
```

PR → review → merge → `git switch main; git pull`.

> From now on, to change Step 0: `terraform init -backend-config="..\backend.hcl"` first.

---

## Part 9 — Connect GitHub to Azure (OIDC)

### 9a. Turn on elevated access
portal.azure.com → **Microsoft Entra ID** → **Properties** →
"Access management for Azure resources" → **Yes** → **Save**. Then:

```powershell
az logout; az login
```

### 9b. Create the pipeline's identity

```powershell
cd C:\CODE\azure-enterprise-landing-zone
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\setup-github-oidc.ps1 -GitHubOwner <your-github-username>
```

### 9c. Secrets and variables
Repo → **Settings → Secrets and variables → Actions** — copy the values the
script printed:

| Tab | Name | Value |
|---|---|---|
| Secrets | `AZURE_CLIENT_ID` | from the script |
| Secrets | `AZURE_TENANT_ID` | from the script |
| Secrets | `AZURE_SUBSCRIPTION_ID` | from the script |
| Variables | `TFSTATE_RG` | from the script |
| Variables | `TFSTATE_SA` | from the script |
| Variables | `TF_PREFIX` | `grandhi` |
| Variables | `TF_COMPANY_NAME` | `Grandhi` |
| Variables | `PLATFORM_ADMIN_OBJECT_IDS` | `["<your object id>"]` (brackets and quotes included) |

### 9d. Approval gate
Repo → **Settings → Environments → New environment** → `production` →
✅ **Required reviewers** → add yourself → untick "Prevent self-review" → **Save**.

---

## Part 10 — PR #3: pipeline + Step 1 (from here on, the pipeline applies)

Check `TF_VERSION` in `.github/workflows/terraform.yml` matches your
`terraform version`.

```powershell
git switch -c feature/01-foundation
git add .github 01-foundation
git commit -m "Step 1: management groups, Entra groups, RBAC + CI/CD pipeline"
git push -u origin feature/01-foundation
```

1. Create the PR → **Checks** tab → wait for **plan (01-foundation)** to go green.
2. Click it → **Summary** → read the plan. Expect: 7 management groups,
   5 Entra groups, ~10 role assignments, 1 subscription move, 1 group member.
3. **Merge** → **Actions** tab → the run says *Waiting* →
   **Review deployments** → ✅ production → **Approve and deploy**.
4. Check:
   ```powershell
   az account management-group show --name grandhi --expand --recurse -o table
   ```
5. `git switch main; git pull`

---

## Part 11 — Lock it down

1. **Require the plan to pass before merging:** Settings → Rules → Rulesets →
   `protect-main` → ✅ **Require status checks to pass** → add
   `plan (01-foundation)` → Save.
2. **Turn elevated access off** (same switch as 9a → **No**). You keep access
   through `grp-grandhi-platform-admins`.

---

## Part 12 — PR #4: Step 2 (policy)

```powershell
git switch -c feature/02-policy
```

In `.github/workflows/terraform.yml`, in **both** matrix lists, change
`step: ["01-foundation"]` → `step: ["01-foundation", "02-policy"]`.

```powershell
git add .github 02-policy
git commit -m "Step 2: policy guardrails (regions, tags, storage security)"
git push -u origin feature/02-policy
```

Same flow: PR → plan → merge → approve. The plan for `01-foundation` should
say **No changes**. Afterwards add `plan (02-policy)` as a required check too.

---

## Daily flow

```powershell
git switch main; git pull                      # start from the latest
git switch -c feature/<short-name>             # new branch
# ...edit .tf files...
terraform fmt -recursive                       # tidy formatting
terraform plan                                 # check locally — plan only!
git add <files>; git commit -m "<what and why>"
git push -u origin feature/<short-name>        # → PR → review plan → merge → approve
```

**Rule:** never `terraform apply` from a laptop on anything the pipeline manages.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `AADSTS700213` / `No matching federated identity record` | Repo name, username or environment name doesn't match the trust | Re-run the setup script with the exact GitHub username; environment must be named `production` |
| `403` / `AuthorizationPermissionMismatch` on the state blob | Storage role not active yet | Wait 5–10 minutes and re-run |
| `Authorization_RequestDenied` creating groups | Graph admin consent missing | Entra ID → App registrations → the app → API permissions → **Grant admin consent** |
| `AuthorizationFailed` on management groups | Pipeline missing Owner at Tenant Root | Re-run the setup script with elevated access on |
| `terraform fmt -check` fails | Formatting differences | `terraform fmt -recursive` locally, commit, push |
| `Error acquiring the state lock` | Another run is still going, or one crashed | Wait; if stuck, `terraform force-unlock <LOCK_ID>` locally |
| `ScopeLocked` during destroy | Delete lock still on the resource group | Destroy the lock first (Part 0) |

## Real-world upgrades (good interview talking points)

- **Two pipeline identities:** a read-only one for PR plans, a write one for
  apply — a PR from a branch can then never change Azure.
- **Narrower roles:** Owner at Tenant Root keeps a lab simple; in production,
  scope it to the company management group and use PIM for humans.
- **Security scanning in the PR:** add `checkov` or `trivy` as a step.
- **Drift detection:** a nightly scheduled `plan` that alerts if someone
  changed things in the portal.
