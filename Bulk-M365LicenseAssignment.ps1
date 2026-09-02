<#
.SYNOPSIS
    Bulk-assigns Microsoft 365 licenses to users from a CSV input file.

.DESCRIPTION
    Reads a CSV containing UserPrincipalNames and a target license SKU,
    connects to Microsoft Graph, and assigns the specified license to each
    user. Logs successes and failures to a report file for auditing.

    Designed for scenarios like onboarding batches, department-wide license
    rollouts, or post-migration license cleanup.

.PARAMETER CsvPath
    Path to a CSV file with a single column header "UserPrincipalName"
    listing the users to license.

.PARAMETER SkuPartNumber
    The license SKU to assign (e.g. "ENTERPRISEPACK" for Office 365 E3,
    "SPE_E5" for Microsoft 365 E5). Run Get-MgSubscribedSku to see SKUs
    available in your tenant.

.PARAMETER LogPath
    Where to write the result log. Defaults to .\LicenseAssignment-Log.csv
    in the current directory.

.EXAMPLE
    .\Bulk-M365LicenseAssignment.ps1 -CsvPath ".\NewHires.csv" -SkuPartNumber "ENTERPRISEPACK"

.NOTES
    Author: Prachi Gavhane
    Requires: Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement modules
    Scopes needed: User.ReadWrite.All, Organization.Read.All
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [string]$SkuPartNumber,

    [string]$LogPath = ".\LicenseAssignment-Log.csv"
)

# Connect to Microsoft Graph with the scopes needed for license management
try {
    Connect-MgGraph -Scopes "User.ReadWrite.All", "Organization.Read.All" -ErrorAction Stop
    Write-Host "Connected to Microsoft Graph." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

# Resolve the SKU ID from the friendly part number
$sku = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq $SkuPartNumber }

if (-not $sku) {
    Write-Error "SKU '$SkuPartNumber' not found in this tenant. Run Get-MgSubscribedSku to list available SKUs."
    exit 1
}

# Check available seats before starting the batch
$availableUnits = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
Write-Host "SKU '$SkuPartNumber' has $availableUnits license(s) available." -ForegroundColor Cyan

# Import the user list
$users = Import-Csv -Path $CsvPath

if (-not $users -or -not ($users | Get-Member -Name "UserPrincipalName")) {
    Write-Error "CSV must contain a 'UserPrincipalName' column."
    exit 1
}

if ($users.Count -gt $availableUnits) {
    Write-Warning "Requested $($users.Count) licenses but only $availableUnits are available. Some assignments will fail."
}

$results = New-Object System.Collections.Generic.List[Object]
$successCount = 0
$failCount = 0

foreach ($user in $users) {
    $upn = $user.UserPrincipalName.Trim()

    if ([string]::IsNullOrWhiteSpace($upn)) {
        continue
    }

    try {
        # Verify user exists before attempting assignment
        $mgUser = Get-MgUser -UserId $upn -ErrorAction Stop

        # Some SKUs require a usage location to be set before licensing
        if (-not $mgUser.UsageLocation) {
            Update-MgUser -UserId $upn -UsageLocation "IN"
        }

        $licenseParams = @{
            AddLicenses    = @(@{ SkuId = $sku.SkuId })
            RemoveLicenses = @()
        }

        Set-MgUserLicense -UserId $upn -BodyParameter $licenseParams -ErrorAction Stop

        $results.Add([PSCustomObject]@{
            UserPrincipalName = $upn
            Status            = "Success"
            SkuAssigned       = $SkuPartNumber
            Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Error             = ""
        })
        $successCount++
        Write-Host "[OK] $upn -> $SkuPartNumber" -ForegroundColor Green
    }
    catch {
        $results.Add([PSCustomObject]@{
            UserPrincipalName = $upn
            Status            = "Failed"
            SkuAssigned       = $SkuPartNumber
            Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Error             = $_.Exception.Message
        })
        $failCount++
        Write-Host "[FAIL] $upn -> $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Export results for audit trail
$results | Export-Csv -Path $LogPath -NoTypeInformation

Write-Host "`nDone. Success: $successCount | Failed: $failCount" -ForegroundColor Cyan
Write-Host "Full log written to $LogPath" -ForegroundColor Cyan

Disconnect-MgGraph | Out-Null
