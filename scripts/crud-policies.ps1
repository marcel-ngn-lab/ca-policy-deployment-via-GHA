# Connect to Microsoft Graph
$ApplicationId = $env:AZURE_CLIENT_ID
$SecuredPassword = $env:AZURE_CLIENT_SECRET
$tenantID = $env:AZURE_TENANT_ID
$ntfyUrl = $env:NTFY_URL
$workflowName = $env:WORKFLOW_NAME
$runId = $env:RUN_ID

# Create secure credential
$SecuredPasswordPassword = ConvertTo-SecureString -String $SecuredPassword -AsPlainText -Force
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ApplicationId, $SecuredPasswordPassword

# Connect to Microsoft Graph
Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $ClientSecretCredential | Out-Null

# Define the path to the directory containing your JSON files
$jsonFilesDirectory = "./policies/"

# Get all JSON files in the directory
$jsonFiles = Get-ChildItem -Path $jsonFilesDirectory -Filter *.json

# Initialize counters for summary
$created = 0
$updated = 0
$unchanged = 0
$removed = 0
$failed = 0
$summary = @()

# Get existing policies
Write-Host "Retrieving existing policies..." -ForegroundColor Cyan
$existingPolicies = Get-MgIdentityConditionalAccessPolicy

# Create a hashtable of policies defined in JSON files
$definedPolicies = @{}
if ($jsonFiles.Count -gt 0) {
    foreach ($jsonFile in $jsonFiles) {
        try {
            $policyJson = Get-Content -Path $jsonFile.FullName | ConvertFrom-Json
            $definedPolicies[$policyJson.displayName] = $jsonFile.FullName
        } catch {
            Write-Host "Error reading policy file $($jsonFile.FullName): $_" -ForegroundColor Red
            $failed++
            $summary += "FAILED TO READ: $($jsonFile.FullName) - Error: $_"
        }
    }
}

# Helper function to normalize objects for comparison
function Normalize-PolicyObject {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PolicyObject
    )
    
    # Create a clean normalized object
    $normalized = @{
        displayName = $null
        state = $null
        conditions = @{}
        grantControls = @{}
        sessionControls = $null
    }
    
    # Handle displayName - could be DisplayName or displayName
    if ($PolicyObject.PSObject.Properties.Name -contains "DisplayName") {
        $normalized.displayName = $PolicyObject.DisplayName
    } elseif ($PolicyObject.PSObject.Properties.Name -contains "displayName") {
        $normalized.displayName = $PolicyObject.displayName
    }
    
    # Handle state - could be State or state
    if ($PolicyObject.PSObject.Properties.Name -contains "State") {
        $normalized.state = $PolicyObject.State.ToLower()
    } elseif ($PolicyObject.PSObject.Properties.Name -contains "state") {
        $normalized.state = $PolicyObject.state.ToLower()
    }
    
    # Handle conditions - could be Conditions or conditions
    $conditionsProperty = $null
    if ($PolicyObject.PSObject.Properties.Name -contains "Conditions") {
        $conditionsProperty = $PolicyObject.Conditions
    } elseif ($PolicyObject.PSObject.Properties.Name -contains "conditions") {
        $conditionsProperty = $PolicyObject.conditions
    }
    
    if ($null -ne $conditionsProperty) {
        # Only include non-null values
        $conditionProperties = $conditionsProperty | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        foreach ($prop in $conditionProperties) {
            if ($null -ne $conditionsProperty.$prop) {
                $normalized.conditions[$prop] = $conditionsProperty.$prop
            }
        }
    }
    
    # Handle grantControls - could be GrantControls or grantControls
    $grantControlsProperty = $null
    if ($PolicyObject.PSObject.Properties.Name -contains "GrantControls") {
        $grantControlsProperty = $PolicyObject.GrantControls
    } elseif ($PolicyObject.PSObject.Properties.Name -contains "grantControls") {
        $grantControlsProperty = $PolicyObject.grantControls
    }
    
    if ($null -ne $grantControlsProperty) {
        # Only include non-null values
        $grantControlProperties = $grantControlsProperty | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        foreach ($prop in $grantControlProperties) {
            if ($null -ne $grantControlsProperty.$prop) {
                $normalized.grantControls[$prop] = $grantControlsProperty.$prop
            }
        }
    }
    
    # Handle sessionControls - could be SessionControls or sessionControls
    if ($PolicyObject.PSObject.Properties.Name -contains "SessionControls") {
        $normalized.sessionControls = $PolicyObject.SessionControls
    } elseif ($PolicyObject.PSObject.Properties.Name -contains "sessionControls") {
        $normalized.sessionControls = $PolicyObject.sessionControls
    }
    
    return $normalized
}

# First, process existing policies that need to be updated or removed
foreach ($existingPolicy in $existingPolicies) {
    # Skip policies that don't follow our managed naming convention
    if (!$existingPolicy.DisplayName.StartsWith("GH - ")) { continue }
    
    if ($definedPolicies.ContainsKey($existingPolicy.DisplayName)) {
        # Policy exists in repo - it will be processed in the next loop
        continue
    } else {
        # Policy exists in Azure but not in repo - delete it
        try {
            Write-Host "Removing policy no longer in repository: $($existingPolicy.DisplayName)" -ForegroundColor Magenta
            Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id
            Write-Host "Policy removed successfully: $($existingPolicy.DisplayName)" -ForegroundColor Green
            $removed++
            $summary += "REMOVED: $($existingPolicy.DisplayName)"
        } catch {
            Write-Host "Error removing policy $($existingPolicy.DisplayName): $_" -ForegroundColor Red
            $failed++
            $summary += "FAILED TO REMOVE: $($existingPolicy.DisplayName) - Error: $_"
        }
    }
}

# Now process the JSON files for creation/update
foreach ($jsonFile in $jsonFiles) {
    try {
        # Read the content of the JSON file and convert it to a PowerShell object
        $policyJson = Get-Content -Path $jsonFile.FullName | ConvertFrom-Json

        # Create a custom object
        $policyObject = [PSCustomObject]@{
            displayName     = $policyJson.displayName
            conditions      = $policyJson.conditions
            grantControls   = $policyJson.grantControls
            sessionControls = $policyJson.sessionControls
            state           = $policyJson.state
        }

        # Convert the custom object to JSON with a depth of 10
        $policyJsonString = $policyObject | ConvertTo-Json -Depth 10

        # Check if a policy with the same display name already exists
        $existingPolicy = $existingPolicies | Where-Object { $_.DisplayName -eq $policyJson.displayName }

        if ($existingPolicy) {
            # Normalize both objects for comparison
            $normalizedExisting = Normalize-PolicyObject -PolicyObject $existingPolicy
            $normalizedNew = Normalize-PolicyObject -PolicyObject $policyObject
            
            # Convert to JSON for comparison, but sort properties to ensure consistent order
            $existingJson = $normalizedExisting | ConvertTo-Json -Depth 10 -Compress
            $newJson = $normalizedNew | ConvertTo-Json -Depth 10 -Compress
            
            # Debug - uncomment to see the JSON comparison
            #Write-Host "Existing: $existingJson"
            #Write-Host "New: $newJson"
            
            # Compare using a more focused approach
            $isEqual = $true
            
            # Compare state
            if ($normalizedExisting.state -ne $normalizedNew.state) {
                $isEqual = $false
                Write-Host "  - State differs: '$($normalizedExisting.state)' vs '$($normalizedNew.state)'" -ForegroundColor Gray
            }
            
            # Compare conditions
            $existingCondKeys = $normalizedExisting.conditions.Keys
            $newCondKeys = $normalizedNew.conditions.Keys
            if (($existingCondKeys | Sort-Object) -join ',' -ne ($newCondKeys | Sort-Object) -join ',') {
                $isEqual = $false
                Write-Host "  - Condition keys differ" -ForegroundColor Gray
            } else {
                foreach ($key in $existingCondKeys) {
                    $existingCondJson = $normalizedExisting.conditions[$key] | ConvertTo-Json -Depth 10 -Compress
                    $newCondJson = $normalizedNew.conditions[$key] | ConvertTo-Json -Depth 10 -Compress
                    if ($existingCondJson -ne $newCondJson) {
                        $isEqual = $false
                        Write-Host "  - Condition '$key' differs" -ForegroundColor Gray
                    }
                }
            }
            
            # Compare grant controls
            $existingGrantKeys = $normalizedExisting.grantControls.Keys
            $newGrantKeys = $normalizedNew.grantControls.Keys
            if (($existingGrantKeys | Sort-Object) -join ',' -ne ($newGrantKeys | Sort-Object) -join ',') {
                $isEqual = $false
                Write-Host "  - Grant control keys differ" -ForegroundColor Gray
            } else {
                foreach ($key in $existingGrantKeys) {
                    $existingGrantJson = $normalizedExisting.grantControls[$key] | ConvertTo-Json -Depth 10 -Compress
                    $newGrantJson = $normalizedNew.grantControls[$key] | ConvertTo-Json -Depth 10 -Compress
                    if ($existingGrantJson -ne $newGrantJson) {
                        $isEqual = $false
                        Write-Host "  - Grant control '$key' differs" -ForegroundColor Gray
                    }
                }
            }
            
            # Compare session controls
            if ($null -ne $normalizedExisting.sessionControls -or $null -ne $normalizedNew.sessionControls) {
                $existingSessionJson = $normalizedExisting.sessionControls | ConvertTo-Json -Depth 10 -Compress
                $newSessionJson = $normalizedNew.sessionControls | ConvertTo-Json -Depth 10 -Compress
                if ($existingSessionJson -ne $newSessionJson) {
                    $isEqual = $false
                    Write-Host "  - Session controls differ" -ForegroundColor Gray
                }
            }
            
            if ($isEqual) {
                # Policy is unchanged
                Write-Host "Policy unchanged: $($policyJson.displayName)" -ForegroundColor Blue
                $unchanged++
                $summary += "UNCHANGED: $($policyJson.displayName)"
            } else {
                # Update the existing policy
                Write-Host "Policy has changed: $($policyJson.displayName) - Updating..." -ForegroundColor Yellow
                $null = Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id -Body $policyJsonString
                Write-Host "Policy updated successfully: $($policyJson.displayName)" -ForegroundColor Green
                $updated++
                $summary += "UPDATED: $($policyJson.displayName)"
            }
        } else {
            # Create a new policy
            Write-Host "Creating new policy: $($policyJson.displayName)" -ForegroundColor Cyan
            $null = New-MgIdentityConditionalAccessPolicy -Body $policyJsonString
            Write-Host "Policy created successfully: $($policyJson.displayName)" -ForegroundColor Green
            $created++
            $summary += "CREATED: $($policyJson.displayName)"
        }
    }
    catch {
        # Print an error message if an exception occurs
        Write-Host "An error occurred while processing the policy file '$($jsonFile.FullName)': $_" -ForegroundColor Red
        $failed++
        $summary += "FAILED: $($jsonFile.Name) - Error: $_"
    }
}

# Print summary
Write-Host "`nDEPLOYMENT SUMMARY:" -ForegroundColor Cyan
Write-Host "Policies Created: $created" -ForegroundColor Green
Write-Host "Policies Updated: $updated" -ForegroundColor Yellow
Write-Host "Policies Unchanged: $unchanged" -ForegroundColor Blue
Write-Host "Policies Removed: $removed" -ForegroundColor Magenta
Write-Host "Operations Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "`nDetailed Results:" -ForegroundColor Cyan
$summary | ForEach-Object { Write-Host $_ }

# Send notification
Write-Host "`nSending notification..." -ForegroundColor Cyan

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

$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$message = @"
## Conditional Access Policy Deployment Summary

**Time**: $timestamp
**Workflow**: $workflowName
**Run ID**: $runId

### Results:
- ✅ Created: $created
- 🔄 Updated: $updated
- 📋 Unchanged: $unchanged
- 🗑️ Removed: $removed
- ❌ Failed: $failed

"@

# Add details if there are any
if ($summary.Count -gt 0) {
    $message += "### Details:`n"
    foreach ($detail in $summary) {
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
    Write-Host "Sending notification to $ntfyUrl" -ForegroundColor Cyan
    Invoke-RestMethod -Method Post -Uri $ntfyUrl -Headers $headers -Body $message
    Write-Host "Notification sent successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to send notification: $_" -ForegroundColor Red
    # Continue execution even if notification fails
}