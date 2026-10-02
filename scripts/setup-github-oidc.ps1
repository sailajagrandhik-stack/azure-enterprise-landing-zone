<#
  ONE-TIME SETUP: lets the GitHub pipeline sign in to Azure without any password.

  What it creates:
    1. An Entra app + service principal  = the pipeline's identity
    2. Two "federated credentials"       = "trust tokens from THIS GitHub repo"
         - pull requests       (for plan)
         - environment production (for apply)
    3. Azure roles for the pipeline:
         - Owner on Tenant Root Group   (to build management groups + RBAC)
         - Storage Blob Data Contributor on the state storage account
    4. Microsoft Graph permissions (to create Entra groups) + admin consent

  Run from the project folder, signed in with `az login` as a Global Admin
  with "elevated access" turned on:

    .\scripts\setup-github-oidc.ps1 -GitHubOwner <your-github-username>
#>
param(
  [Parameter(Mandatory = $true)] [string] $GitHubOwner,
  [string] $RepoName = "azure-enterprise-landing-zone",
  [string] $AppName  = "sp-github-azure-enterprise-landing-zone"
)

$tenantId = az account show --query tenantId -o tsv
$subId    = az account show --query id -o tsv

# Read state storage names from backend.hcl (created in step 0)
$backend = Get-Content (Join-Path $PSScriptRoot "..\backend.hcl") -Raw
$rg = [regex]::Match($backend, 'resource_group_name\s*=\s*"([^"]+)"').Groups[1].Value
$sa = [regex]::Match($backend, 'storage_account_name\s*=\s*"([^"]+)"').Groups[1].Value
if (-not $rg -or -not $sa) { throw "Could not read backend.hcl — run step 0 first." }

Write-Host "`n[1/4] Pipeline identity" -ForegroundColor Cyan
$appId = az ad app list --display-name $AppName --query "[0].appId" -o tsv
if (-not $appId) {
  $appId = az ad app create --display-name $AppName --query appId -o tsv
  az ad sp create --id $appId | Out-Null
  Start-Sleep -Seconds 15   # give Entra a moment to catch up
}
$spObjectId = az ad sp show --id $appId --query id -o tsv
Write-Host "    appId = $appId"

Write-Host "`n[2/4] Trust GitHub repo $GitHubOwner/$RepoName" -ForegroundColor Cyan
$creds = @(
  @{ name = "github-pull-request"; subject = "repo:${GitHubOwner}/${RepoName}:pull_request" },
  @{ name = "github-production";   subject = "repo:${GitHubOwner}/${RepoName}:environment:production" }
)
$existing = az ad app federated-credential list --id $appId --query "[].name" -o tsv
foreach ($c in $creds) {
  if ($existing -contains $c.name) { Write-Host "    exists: $($c.name)"; continue }
  $tmp = New-TemporaryFile
  @{
    name      = $c.name
    issuer    = "https://token.actions.githubusercontent.com"
    subject   = $c.subject
    audiences = @("api://AzureADTokenExchange")
  } | ConvertTo-Json | Out-File -Encoding ascii $tmp
  az ad app federated-credential create --id $appId --parameters "@$tmp" | Out-Null
  Remove-Item $tmp
  Write-Host "    added: $($c.subject)"
}

Write-Host "`n[3/4] Azure roles" -ForegroundColor Cyan
az role assignment create --assignee-object-id $spObjectId --assignee-principal-type ServicePrincipal `
  --role "Owner" --scope "/providers/Microsoft.Management/managementGroups/$tenantId" | Out-Null
Write-Host "    Owner on Tenant Root Group"
$saId = az storage account show -n $sa -g $rg --query id -o tsv
az role assignment create --assignee-object-id $spObjectId --assignee-principal-type ServicePrincipal `
  --role "Storage Blob Data Contributor" --scope $saId | Out-Null
Write-Host "    Storage Blob Data Contributor on $sa"

Write-Host "`n[4/4] Microsoft Graph permissions (Group.ReadWrite.All, User.Read.All)" -ForegroundColor Cyan
az ad app permission add --id $appId --api 00000003-0000-0000-c000-000000000000 `
  --api-permissions 62a82d76-70ea-41e2-9197-370581804d09=Role df021288-bdef-4463-88db-98f22de89214=Role 2>$null
Start-Sleep -Seconds 20
az ad app permission admin-consent --id $appId
Write-Host "    granted (admin consent)"

$me = az ad signed-in-user show --query id -o tsv

Write-Host "`n================ COPY THESE INTO GITHUB ================" -ForegroundColor Green
Write-Host "Repo → Settings → Secrets and variables → Actions"
Write-Host "`n  SECRETS tab:"
Write-Host "    AZURE_CLIENT_ID        = $appId"
Write-Host "    AZURE_TENANT_ID        = $tenantId"
Write-Host "    AZURE_SUBSCRIPTION_ID  = $subId"
Write-Host "`n  VARIABLES tab:"
Write-Host "    TFSTATE_RG                 = $rg"
Write-Host "    TFSTATE_SA                 = $sa"
Write-Host "    TF_PREFIX                  = grandhi"
Write-Host "    TF_COMPANY_NAME            = Grandhi"
Write-Host "    PLATFORM_ADMIN_OBJECT_IDS  = [`"$me`"]"
Write-Host "=========================================================`n"
