$policyDefinition = Get-Content -Path "./policies/policy.json" | ConvertFrom-Json

if (-not $policyDefinition) {
    throw "Failed to parse policy JSON."
}

$params = @{
    DisplayName      = $policyDefinition.displayName
    Conditions       = $policyDefinition.conditions
    GrantControls    = $policyDefinition.grantControls
    SessionControls  = $policyDefinition.sessionControls
    State            = $policyDefinition.state
}

$existingPolicy = Get-MgIdentityConditionalAccessPolicy | Where-Object { $_.DisplayName -eq $policyDefinition.displayName }

if ($existingPolicy) {
    Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id @params
    Write-Output "Updated existing policy: $($policyDefinition.displayName)"
} else {
    New-MgIdentityConditionalAccessPolicy @params
    Write-Output "Created new policy: $($policyDefinition.displayName)"
}