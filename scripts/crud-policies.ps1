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

# Helper function to compare policy content for functional equivalence
function Compare-PolicyContent {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ExistingPolicy,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$NewPolicy
    )
    
    # Get state (enabled/disabled)
    $existingState = if ($ExistingPolicy.State) { $ExistingPolicy.State.ToLower() } else { $ExistingPolicy.state.ToLower() }
    $newState = if ($NewPolicy.State) { $NewPolicy.State.ToLower() } else { $NewPolicy.state.ToLower() }
    
    if ($existingState -ne $newState) {
        Write-Host "  - State differs: $existingState vs $newState" -ForegroundColor Gray
        return $false
    }
    
    # Helper function to extract core values from either property naming convention
    function Get-PropertyValue {
        param ($Obj, $PropertyName)
        
        $upperName = $PropertyName.Substring(0, 1).ToUpper() + $PropertyName.Substring(1)
        $lowerName = $PropertyName.Substring(0, 1).ToLower() + $PropertyName.Substring(1)
        
        if ($null -ne $Obj.$upperName) {
            return $Obj.$upperName
        } elseif ($null -ne $Obj.$lowerName) {
            return $Obj.$lowerName
        } else {
            return $null
        }
    }
    
    # Get conditions
    $existingConditions = Get-PropertyValue -Obj $ExistingPolicy -PropertyName "Conditions"
    $newConditions = Get-PropertyValue -Obj $NewPolicy -PropertyName "Conditions"
    
    # Compare applications
    $existingApps = Get-PropertyValue -Obj $existingConditions -PropertyName "Applications"
    $newApps = Get-PropertyValue -Obj $newConditions -PropertyName "Applications"
    
    if ($existingApps -and $newApps) {
        # Compare include applications
        $existingIncludes = $existingApps.IncludeApplications -join ','
        $newIncludes = $newApps.includeApplications -join ','
        
        if ($existingIncludes -ne $newIncludes) {
            Write-Host "  - Include applications differ: $existingIncludes vs $newIncludes" -ForegroundColor Gray
            return $false
        }
        
        # Compare exclude applications
        $existingExcludes = if ($existingApps.ExcludeApplications) { $existingApps.ExcludeApplications -join ',' } else { "" }
        $newExcludes = if ($newApps.excludeApplications) { $newApps.excludeApplications -join ',' } else { "" }
        
        if ($existingExcludes -ne $newExcludes) {
            Write-Host "  - Exclude applications differ" -ForegroundColor Gray
            return $false
        }
    }
    
    # Compare users
    $existingUsers = Get-PropertyValue -Obj $existingConditions -PropertyName "Users"
    $newUsers = Get-PropertyValue -Obj $newConditions -PropertyName "Users"
    
    if ($existingUsers -and $newUsers) {
        # Compare include users
        $existingIncludes = $existingUsers.IncludeUsers -join ','
        $newIncludes = $newUsers.includeUsers -join ','
        
        if ($existingIncludes -ne $newIncludes) {
            Write-Host "  - Include users differ" -ForegroundColor Gray
            return $false
        }
        
        # Compare exclude users
        $existingExcludes = if ($existingUsers.ExcludeUsers) { $existingUsers.ExcludeUsers -join ',' } else { "" }
        $newExcludes = if ($newUsers.excludeUsers) { $newUsers.excludeUsers -join ',' } else { "" }
        
        if ($existingExcludes -ne $newExcludes) {
            Write-Host "  - Exclude users differ" -ForegroundColor Gray
            return $false
        }
        
        # Compare include groups
        $existingGroups = if ($existingUsers.IncludeGroups) { $existingUsers.IncludeGroups -join ',' } else { "" }
        $newGroups = if ($newUsers.includeGroups) { $newUsers.includeGroups -join ',' } else { "" }
        
        if ($existingGroups -ne $newGroups) {
            Write-Host "  - Include groups differ" -ForegroundColor Gray
            return $false
        }
        
        # Compare exclude groups
        $existingExGroups = if ($existingUsers.ExcludeGroups) { $existingUsers.ExcludeGroups -join ',' } else { "" }
        $newExGroups = if ($newUsers.excludeGroups) { $newUsers.excludeGroups -join ',' } else { "" }
        
        if ($existingExGroups -ne $newExGroups) {
            Write-Host "  - Exclude groups differ" -ForegroundColor Gray
            return $false
        }
        
        # Compare include roles
        $existingRoles = if ($existingUsers.IncludeRoles) { $existingUsers.IncludeRoles -join ',' } else { "" }
        $newRoles = if ($newUsers.includeRoles) { $newUsers.includeRoles -join ',' } else { "" }
        
        if ($existingRoles -ne $newRoles) {
            Write-Host "  - Include roles differ" -ForegroundColor Gray
            return $false
        }
        
        # Compare exclude roles
        $existingExRoles = if ($existingUsers.ExcludeRoles) { $existingUsers.ExcludeRoles -join ',' } else { "" }
        $newExRoles = if ($newUsers.excludeRoles) { $newUsers.excludeRoles -join ',' } else { "" }
        
        if ($existingExRoles -ne $newExRoles) {
            Write-Host "  - Exclude roles differ" -ForegroundColor Gray
            return $false
        }
    }
    
    # Compare platforms
    $existingPlatforms = Get-PropertyValue -Obj $existingConditions -PropertyName "Platforms"
    $newPlatforms = Get-PropertyValue -Obj $newConditions -PropertyName "Platforms"
    
    if ($existingPlatforms -and $newPlatforms) {
        # Compare include platforms
        $existingIncludes = if ($existingPlatforms.IncludePlatforms) { $existingPlatforms.IncludePlatforms -join ',' } else { "" }
        $newIncludes = if ($newPlatforms.includePlatforms) { $newPlatforms.includePlatforms -join ',' } else { "" }
        
        if ($existingIncludes -ne $newIncludes) {
            Write-Host "  - Include platforms differ" -ForegroundColor Gray
            return $false
        }
        
        # Compare exclude platforms
        $existingExcludes = if ($existingPlatforms.ExcludePlatforms) { $existingPlatforms.ExcludePlatforms -join ',' } else { "" }
        $newExcludes = if ($newPlatforms.excludePlatforms) { $newPlatforms.excludePlatforms -join ',' } else { "" }
        
        if ($existingExcludes -ne $newExcludes) {
            Write-Host "  - Exclude platforms differ" -ForegroundColor Gray
            return $false
        }
    }
    
    # Compare locations
    $existingLocations = Get-PropertyValue -Obj $existingConditions -PropertyName "Locations"
    $newLocations = Get-PropertyValue -Obj $newConditions -PropertyName "Locations"
    
    if ($existingLocations -and $newLocations) {
        # Compare include locations
        $existingIncludes = if ($existingLocations.IncludeLocations) { $existingLocations.IncludeLocations -join ',' } else { "" }
        $newIncludes = if ($newLocations.includeLocations) { $newLocations.includeLocations -join ',' } else { "" }
        
        if ($existingIncludes -ne $newIncludes) {
            Write-Host "  - Include locations differ" -ForegroundColor Gray
            return $false
        }
        
        # Compare exclude locations
        $existingExcludes = if ($existingLocations.ExcludeLocations) { $existingLocations.ExcludeLocations -join ',' } else { "" }
        $newExcludes = if ($newLocations.excludeLocations) { $newLocations.excludeLocations -join ',' } else { "" }
        
        if ($existingExcludes -ne $newExcludes) {
            Write-Host "  - Exclude locations differ" -ForegroundColor Gray
            return $false
        }
    }
    
    # Compare client app types
    $existingClientApps = if ($existingConditions.ClientAppTypes) { $existingConditions.ClientAppTypes -join ',' } else { "" }
    $newClientApps = if ($newConditions.clientAppTypes) { $newConditions.clientAppTypes -join ',' } else { "" }
    
    if ($existingClientApps -ne $newClientApps) {
        Write-Host "  - Client app types differ" -ForegroundColor Gray
        return $false
    }
    
    # Compare grant controls
    $existingGrantControls = Get-PropertyValue -Obj $ExistingPolicy -PropertyName "GrantControls"
    $newGrantControls = Get-PropertyValue -Obj $NewPolicy -PropertyName "GrantControls"
    
    if ($existingGrantControls -and $newGrantControls) {
        # Compare operator
        $existingOperator = $existingGrantControls.Operator.ToLower()
        $newOperator = $newGrantControls.operator.ToLower()
        
        if ($existingOperator -ne $newOperator) {
            Write-Host "  - Grant control operator differs" -ForegroundColor Gray
            return $false
        }
        
        # Compare built-in controls
        $existingBuiltIn = if ($existingGrantControls.BuiltInControls) { $existingGrantControls.BuiltInControls -join ',' } else { "" }
        $newBuiltIn = if ($newGrantControls.builtInControls) { $newGrantControls.builtInControls -join ',' } else { "" }
        
        if ($existingBuiltIn -ne $newBuiltIn) {
            Write-Host "  - Built-in controls differ" -ForegroundColor Gray
            return $false
        }
        
        # Compare custom controls
        $existingCustom = if ($existingGrantControls.CustomAuthenticationFactors) { $existingGrantControls.CustomAuthenticationFactors -join ',' } else { "" }
        $newCustom = if ($newGrantControls.customAuthenticationFactors) { $newGrantControls.customAuthenticationFactors -join ',' } else { "" }
        
        if ($existingCustom -ne $newCustom) {
            Write-Host "  - Custom controls differ" -ForegroundColor Gray
            return $false
        }
    }
    
    # Compare session controls if they exist
    $existingSessionControls = Get-PropertyValue -Obj $ExistingPolicy -PropertyName "SessionControls"
    $newSessionControls = Get-PropertyValue -Obj $NewPolicy -PropertyName "SessionControls"
    
    # If one has session controls and the other doesn't, they're different
    if (($null -ne $existingSessionControls -and $null -eq $newSessionControls) -or 
        ($null -eq $existingSessionControls -and $null -ne $newSessionControls)) {
        Write-Host "  - Session controls presence differs" -ForegroundColor Gray
        return $false
    }
    
    # If both have session controls, compare them
    if ($null -ne $existingSessionControls -and $null -ne $newSessionControls) {
        # Compare application enforced restrictions
        $existingAppEnforced = if ($existingSessionControls.ApplicationEnforcedRestrictions) { $existingSessionControls.ApplicationEnforcedRestrictions.IsEnabled } else { $false }
        $newAppEnforced = if ($newSessionControls.applicationEnforcedRestrictions) { $newSessionControls.applicationEnforcedRestrictions.isEnabled } else { $false }
        
        if ($existingAppEnforced -ne $newAppEnforced) {
            Write-Host "  - Application enforced restrictions differ" -ForegroundColor Gray
            return $false
        }
        
        # Compare cloud app security
        $existingCloudAppSecurity = if ($existingSessionControls.CloudAppSecurity) { $existingSessionControls.CloudAppSecurity.IsEnabled } else { $false }
        $newCloudAppSecurity = if ($newSessionControls.cloudAppSecurity) { $newSessionControls.cloudAppSecurity.isEnabled } else { $false }
        
        if ($existingCloudAppSecurity -ne $newCloudAppSecurity) {
            Write-Host "  - Cloud app security differ" -ForegroundColor Gray
            return $false
        }
        
        # Compare sign-in frequency
        $existingSignInFrequency = if ($existingSessionControls.SignInFrequency) { $existingSessionControls.SignInFrequency.IsEnabled } else { $false }
        $newSignInFrequency = if ($newSessionControls.signInFrequency) { $newSessionControls.signInFrequency.isEnabled } else { $false }
        
        if ($existingSignInFrequency -ne $newSignInFrequency) {
            Write-Host "  - Sign-in frequency differ" -ForegroundColor Gray
            return $false
        }
        
        # If sign-in frequency is enabled, compare the values
        if ($existingSignInFrequency -and $newSignInFrequency) {
            $existingValue = $existingSessionControls.SignInFrequency.Value
            $newValue = $newSessionControls.signInFrequency.value
            
            if ($existingValue -ne $newValue) {
                Write-Host "  - Sign-in frequency value differs" -ForegroundColor Gray
                return $false
            }
            
            $existingType = $existingSessionControls.SignInFrequency.Type
            $newType = $newSessionControls.signInFrequency.type
            
            if ($existingType -ne $newType) {
                Write-Host "  - Sign-in frequency type differs" -ForegroundColor Gray
                return $false
            }
        }
        
        # Compare persistent browser
        $existingPersistentBrowser = if ($existingSessionControls.PersistentBrowser) { $existingSessionControls.PersistentBrowser.IsEnabled } else { $false }
        $newPersistentBrowser = if ($newSessionControls.persistentBrowser) { $newSessionControls.persistentBrowser.isEnabled } else { $false }
        
        if ($existingPersistentBrowser -ne $newPersistentBrowser) {
            Write-Host "  - Persistent browser differ" -ForegroundColor Gray
            return $false
        }
        
        # If persistent browser is enabled, compare the mode
        if ($existingPersistentBrowser -and $newPersistentBrowser) {
            $existingMode = $existingSessionControls.PersistentBrowser.Mode
            $newMode = $newSessionControls.persistentBrowser.mode
            
            if ($existingMode -ne $newMode) {
                Write-Host "  - Persistent browser mode differs" -ForegroundColor Gray
                return $false
            }
        }
    }
    
    # If we got here, the policies are functionally equivalent
    return $true
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
            # Compare policy content for functional equivalence
            $areEquivalent = Compare-PolicyContent -ExistingPolicy $existingPolicy -NewPolicy $policyObject
            
            if ($areEquivalent) {
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