{
  "displayName": "Require MFA for all users",
  "state": "enabled",
  "conditions": {
    "clientAppTypes": ["browser", "mobileAppsAndDesktopClients"],
    "applications": {
      "includeApplications": ["All"]
    },
    "users": {
      "includeUsers": ["All"],
      "excludeUsers": ["<service-principal-id>"]
    },
    "locations": {
      "includeLocations": ["All"]
    },
    "platforms": {
      "includePlatforms": ["all"]
    }
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["mfa"]
  }
}