<#
.SYNOPSIS
    Audits Active Directory user accounts for common security and hygiene issues.

.DESCRIPTION
    Scans a target OU (or the whole domain) for AD user accounts and flags:
      - Stale accounts (no logon within N days)
      - Accounts with passwords that never expire
      - Disabled accounts still in privileged groups
      - Accounts with passwords older than a threshold

    Outputs a CSV report suitable for review with a security or compliance
    team, and can be scheduled to run periodically for ongoing hygiene checks.

.PARAMETER SearchBase
    Distinguished Name of the OU to scan. If omitted, scans the entire domain.

.PARAMETER InactiveDaysThreshold
    Number of days since last logon before an account is flagged as stale.
    Default: 90.

.PARAMETER PasswordAgeThreshold
    Number of days since last password change before flagging as stale.
    Default: 180.

.PARAMETER ReportPath
    Output path for the CSV report. Defaults to .\AD-Audit-Report.csv

.EXAMPLE
    .\AD-AccountAudit.ps1 -SearchBase "OU=Employees,DC=contoso,DC=com" -InactiveDaysThreshold 60

.NOTES
    Author: Prachi Gavhane
    Requires: ActiveDirectory PowerShell module (RSAT)
    Run with an account that has read access to the target OU(s).
#>

[CmdletBinding()]
param (
    [string]$SearchBase,
    [int]$InactiveDaysThreshold = 90,
    [int]$PasswordAgeThreshold = 180,
    [string]$ReportPath = ".\AD-Audit-Report.csv"
)

Import-Module ActiveDirectory -ErrorAction Stop

$inactiveDate = (Get-Date).AddDays(-$InactiveDaysThreshold)
$passwordAgeDate = (Get-Date).AddDays(-$PasswordAgeThreshold)

# Build search parameters conditionally so the script works with or without -SearchBase
$adParams = @{
    Filter     = '*'
    Properties = @(
        'LastLogonDate', 'PasswordLastSet', 'PasswordNeverExpires',
        'Enabled', 'MemberOf', 'DistinguishedName', 'whenCreated'
    )
}
if ($SearchBase) { $adParams['SearchBase'] = $SearchBase }

Write-Host "Scanning Active Directory accounts..." -ForegroundColor Cyan
$users = Get-ADUser @adParams

# Privileged groups worth flagging separately if a disabled account is still a member
$privilegedGroups = @('Domain Admins', 'Enterprise Admins', 'Administrators', 'Schema Admins')

$report = foreach ($user in $users) {

    $flags = New-Object System.Collections.Generic.List[string]

    # Flag 1: Stale / inactive account
    $isStale = $false
    if (-not $user.LastLogonDate) {
        $isStale = $true
        $flags.Add("Never logged on")
    }
    elseif ($user.LastLogonDate -lt $inactiveDate) {
        $isStale = $true
        $flags.Add("Inactive $InactiveDaysThreshold+ days")
    }

    # Flag 2: Password never expires
    if ($user.PasswordNeverExpires) {
        $flags.Add("Password never expires")
    }

    # Flag 3: Password older than threshold
    if ($user.PasswordLastSet -and $user.PasswordLastSet -lt $passwordAgeDate) {
        $flags.Add("Password older than $PasswordAgeThreshold days")
    }

    # Flag 4: Disabled account still in a privileged group
    if (-not $user.Enabled) {
        $userGroups = ($user.MemberOf | ForEach-Object {
            (Get-ADGroup $_ -ErrorAction SilentlyContinue).Name
        })
        $privilegedMembership = $userGroups | Where-Object { $_ -in $privilegedGroups }
        if ($privilegedMembership) {
            $flags.Add("Disabled but still in: $($privilegedMembership -join ', ')")
        }
    }

    if ($flags.Count -gt 0) {
        [PSCustomObject]@{
            SamAccountName   = $user.SamAccountName
            Enabled          = $user.Enabled
            LastLogonDate    = $user.LastLogonDate
            PasswordLastSet  = $user.PasswordLastSet
            OU               = $user.DistinguishedName
            Issues           = ($flags -join "; ")
        }
    }
}

if ($report) {
    $report | Sort-Object Enabled -Descending | Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host "`nAudit complete. $($report.Count) account(s) flagged out of $($users.Count) scanned." -ForegroundColor Yellow
    Write-Host "Report written to $ReportPath" -ForegroundColor Cyan
}
else {
    Write-Host "`nAudit complete. No issues found across $($users.Count) accounts." -ForegroundColor Green
}
