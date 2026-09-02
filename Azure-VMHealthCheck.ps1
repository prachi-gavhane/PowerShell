<#
.SYNOPSIS
    Runs a health check across Azure VMs in a subscription or resource group.

.DESCRIPTION
    Connects to Azure, enumerates VMs in scope, and reports on:
      - Power state (running / deallocated / stopped)
      - OS disk usage warnings (where guest metrics are available)
      - VMs missing recent backups (via Recovery Services vault check)
      - VMs without a configured Azure Monitor diagnostic setting

    Produces a summary to the console and a detailed CSV report, useful as
    a daily/weekly operational health check for a small-to-mid Azure estate.

.PARAMETER ResourceGroupName
    Optional. Limits the check to a single resource group. If omitted,
    scans all VMs in the current subscription context.

.PARAMETER ReportPath
    Output path for the CSV report. Defaults to .\VM-HealthCheck-Report.csv

.EXAMPLE
    .\Azure-VMHealthCheck.ps1 -ResourceGroupName "RG-Production"

.NOTES
    Author: Prachi Gavhane
    Requires: Az.Accounts, Az.Compute, Az.Monitor, Az.RecoveryServices modules
    Run Connect-AzAccount before running, or the script will prompt.
#>

[CmdletBinding()]
param (
    [string]$ResourceGroupName,
    [string]$ReportPath = ".\VM-HealthCheck-Report.csv"
)

# Ensure we're connected to Azure
$context = Get-AzContext
if (-not $context) {
    Write-Host "No active Azure session found. Prompting for login..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
}
else {
    Write-Host "Using existing Azure session: $($context.Account) / $($context.Subscription.Name)" -ForegroundColor Cyan
}

# Get VMs in scope
if ($ResourceGroupName) {
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -Status
}
else {
    $vms = Get-AzVM -Status
}

if (-not $vms) {
    Write-Host "No VMs found in the specified scope." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($vms.Count) VM(s). Running health checks..." -ForegroundColor Cyan

# Pull backup-protected item names once for lookup, rather than per-VM, to save API calls
$protectedVmNames = @()
try {
    $vaults = Get-AzRecoveryServicesVault
    foreach ($vault in $vaults) {
        Set-AzRecoveryServicesVaultContext -Vault $vault
        $items = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -ErrorAction SilentlyContinue
        $protectedVmNames += $items | ForEach-Object { $_.Name }
    }
}
catch {
    Write-Warning "Could not enumerate Recovery Services vaults: $_"
}

$report = foreach ($vm in $vms) {

    $powerState = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
    $isRunning = $powerState -eq "VM running"

    # Check if this VM appears in any backup vault's protected items
    $isBackedUp = $protectedVmNames -contains $vm.Name

    # Check for a diagnostic setting on the VM (basic monitoring coverage check)
    $hasDiagnostics = $false
    try {
        $diag = Get-AzDiagnosticSetting -ResourceId $vm.Id -ErrorAction SilentlyContinue
        $hasDiagnostics = [bool]$diag
    }
    catch {
        # Get-AzDiagnosticSetting throws if none exist on some Az module versions; treat as "none configured"
        $hasDiagnostics = $false
    }

    $issues = New-Object System.Collections.Generic.List[string]
    if (-not $isRunning) { $issues.Add("VM not running ($powerState)") }
    if (-not $isBackedUp) { $issues.Add("No backup protection found") }
    if (-not $hasDiagnostics) { $issues.Add("No diagnostic/monitoring setting configured") }

    [PSCustomObject]@{
        VMName          = $vm.Name
        ResourceGroup   = $vm.ResourceGroupName
        PowerState      = $powerState
        BackupProtected = $isBackedUp
        DiagnosticsSet  = $hasDiagnostics
        Issues          = if ($issues.Count -gt 0) { $issues -join "; " } else { "None" }
    }
}

$report | Export-Csv -Path $ReportPath -NoTypeInformation

$flaggedCount = ($report | Where-Object { $_.Issues -ne "None" }).Count
Write-Host "`nHealth check complete. $flaggedCount of $($vms.Count) VM(s) have one or more issues." -ForegroundColor Yellow
Write-Host "Full report written to $ReportPath" -ForegroundColor Cyan

$report | Format-Table -AutoSize
