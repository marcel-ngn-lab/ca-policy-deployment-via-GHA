param(
    [Parameter(Mandatory=$true)]
    [string]$NtfyUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$SummaryFilePath,
    
    [Parameter(Mandatory=$true)]
    [string]$WorkflowName,
    
    [Parameter(Mandatory=$true)]
    [string]$RunId
)

# Check if summary file exists
if (-not (Test-Path -Path $SummaryFilePath)) {
    Write-Host "Summary file not found at: $SummaryFilePath" -ForegroundColor Red
    # Send basic notification for failure
    $headers = @{
        "Title" = "CA Policy Deployment Failed"
        "Priority" = "high"
        "Tags" = "x"
    }
    $body = "Conditional Access Policy deployment failed. Summary file not found. Workflow: $WorkflowName / Run: $RunId"
    Invoke-RestMethod -Method Post -Uri $NtfyUrl -Headers $headers -Body $body
    exit 1
}

# Read summary file
try {
    $summary = Get-Content -Path $SummaryFilePath -Raw | ConvertFrom-Json
} catch {
    Write-Host "Failed to parse summary JSON: $_" -ForegroundColor Red
    # Send basic notification for failure
    $headers = @{
        "Title" = "CA Policy Deployment Failed"
        "Priority" = "high"
        "Tags" = "x"
    }
    $body = "Conditional Access Policy deployment failed. Could not read summary. Workflow: $WorkflowName / Run: $RunId"
    Invoke-RestMethod -Method Post -Uri $NtfyUrl -Headers $headers -Body $body
    exit 1
}

# Prepare notification content
$created = $summary.created
$updated = $summary.updated
$removed = $summary.removed
$failed = $summary.failed
$timestamp = $summary.timestamp

# Build detailed message
if ($failed -gt 0) {
    $title = "CA Policy Deployment Completed with Errors"
    $priority = "high"
    $tags = "warning"
} else {
    $title = "CA Policy Deployment Successful"
    $priority = "default"
    $tags = "white_check_mark"
}

$message = @"
## Conditional Access Policy Deployment Summary

**Time**: $timestamp
**Workflow**: $WorkflowName
**Run ID**: $RunId

### Results:
- ✅ Created: $created
- 🔄 Updated: $updated
- 🗑️ Removed: $removed
- ❌ Failed: $failed

"@

# Add details if there are any
if ($summary.details.Count -gt 0) {
    $message += "### Details:`n"
    foreach ($detail in $summary.details) {
        $message += "- $detail`n"
    }
}

# Send notification
$headers = @{
    "Title" = $title
    "Priority" = $priority
    "Tags" = $tags
}

try {
    Write-Host "Sending notification to $NtfyUrl" -ForegroundColor Cyan
    Invoke-RestMethod -Method Post -Uri $NtfyUrl -Headers $headers -Body $message
    Write-Host "Notification sent successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to send notification: $_" -ForegroundColor Red
    exit 1
}