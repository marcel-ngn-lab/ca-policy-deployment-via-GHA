# Get policy definition from repository
$policyDefinition = Get-Content -Path "./policies/policy.json" | ConvertFrom-Json

# Check if policy already exists
$existingPolicy = Get-MgIdentityConditionalAccessPolicy | Where-Object {$_.DisplayName -eq $policyDefinition.displayName}

if ($existingPolicy) {
    # Update existing policy
    Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id -BodyParameter $policyDefinition
    Write-Output "Updated existing policy: $($policyDefinition.displayName)"
} else {
    # Create new policy
    New-MgIdentityConditionalAccessPolicy -BodyParameter $policyDefinition
    Write-Output "Created new policy: $($policyDefinition.displayName)"
}