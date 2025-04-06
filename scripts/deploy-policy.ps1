# === Step 2: Load policy JSON ===
$policyPath = "./policies/policy.json"
if (-not (Test-Path $policyPath)) {
    throw "Policy file not found at $policyPath"
}
$policyJsonRaw = Get-Content $policyPath -Raw
$policyObject = $policyJsonRaw | ConvertFrom-Json
$policyName = $policyObject.displayName

# === Step 3: Check if policy exists ===
$response = Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" -Headers $headers
$existingPolicy = $response.value | Where-Object { $_.displayName -eq $policyName }

# === Step 4: Update or Create policy ===
if ($existingPolicy) {
    $policyId = $existingPolicy.id
    Write-Output "🔁 Updating existing policy: $policyName"
    Invoke-RestMethod -Method Patch `
        -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$policyId" `
        -Headers $headers `
        -Body $policyJsonRaw
    Write-Output "✅ Policy updated: $policyName"
} else {
    Write-Output "➕ Creating new policy: $policyName"
    Invoke-RestMethod -Method Post `
        -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" `
        -Headers $headers `
        -Body $policyJsonRaw
    Write-Output "✅ Policy created: $policyName"
}