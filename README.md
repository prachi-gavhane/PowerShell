# PowerShell Automation Scripts

Three scripts built for common cloud/M365 admin operations. Each is documented
with comment-based help — run `Get-Help .\ScriptName.ps1 -Full` for details.

## 1. Bulk-M365LicenseAssignment.ps1
Assigns Microsoft 365 licenses in bulk from a CSV list, using Microsoft Graph.
Handles usage location prerequisites, checks seat availability before running,
and logs every success/failure to a CSV for audit purposes.

**Use case:** Onboarding a new batch of hires, or applying a license change
across a department without doing it one user at a time in the admin center.

## 2. AD-AccountAudit.ps1
Scans Active Directory for common hygiene issues: stale/inactive accounts,
passwords set to never expire, old passwords, and disabled accounts that are
still sitting in privileged groups.

**Use case:** A recurring security hygiene check — the kind of thing an
auditor or security team asks for periodically, done here as one script
instead of manual ADUC review.

## 3. Azure-VMHealthCheck.ps1
Checks Azure VMs for power state, backup protection status, and whether
diagnostic/monitoring settings are configured — flagging anything missing.

**Use case:** A daily/weekly operational check to catch VMs that are stopped
unexpectedly, unprotected by backup, or invisible to monitoring.

---

### How to add these to your GitHub

1. Create a new repo (or use an existing one, e.g. `windows-server-administration`
   or a new `powershell-automation` repo).
2. Add each `.ps1` file with its own short section in the repo's README,
   similar to the descriptions above.
3. In interviews, be ready to walk through: what problem it solves, why you
   chose the approach (e.g. checking seat availability before assignment,
   logging every result for audit trail), and what you'd add next (e.g.
   email notification on failure, scheduling via Task Scheduler/Azure Automation).

### A note on customizing these

These are written to be realistic and complete, but adjust them to match your
actual environment before presenting them as "what I built at work" — e.g.
if your organization uses different SKU names, group names, or thresholds,
update the defaults so the script reflects your real experience accurately.

