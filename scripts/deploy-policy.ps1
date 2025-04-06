# Load and parse the JSON file
$policyJson = Get-Content -Path "./policies/policy.json" -Raw | ConvertFrom-Json

# Build the typed object for GrantControls
$grantControls = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphConditionalAccessGrantControls]::new()
$grantControls.Operator = $policyJson.grantControls.operator
$grantControls.BuiltInControls = $policyJson.grantControls.builtInControls

# Build the typed object for Conditions
$conditions = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphConditionalAccessConditionSet]::new()
$conditions.Applications = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphConditionalAccessApplications]::new()
$conditions.Applications.IncludeApplications = $policyJson.conditions.applications.includeApplications
$conditions.ClientAppTypes = $policyJson.conditions.clientAppTypes
$conditions.Users = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphConditionalAccessUsers]::new()
$conditions.Users.IncludeUsers = $policyJson.conditions.users.includeUsers

# Optional: build SessionControls if you use them
$sessionControls = $null
if ($policyJson.sessionControls) {
    $sessionControls = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphSessionControls]::new()
    # Add specific session controls here if needed
}

# Build the full parameter set
$params = @{
    DisplayName      = $policyJson.displayName
    Conditions       = $conditions
    GrantControls    = $grantControls
    SessionControls  = $sessionControls
    State            = $policyJson.state
}

# Check for existing policy
$existingPolicy = Get-MgIdentityConditionalAccessPolicy | Where-Object { $_.DisplayName -eq $policyJson.displayName }

if ($existingPolicy) {
    Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id @params
    Write-Output "✅ Updated existing policy: $($policyJson.displayName)"
} else {
    New-MgIdentityConditionalAccessPolicy @params
    Write-Output "✅ Created new policy: $($policyJson.displayName)"
}