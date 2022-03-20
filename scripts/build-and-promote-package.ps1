# This script is invoked by the Github Action on pull requests / merges to main
# It relies on two pieces of information being set manually in your sfdx-project.json:
# the versionDescription and versionNumber for the default package. Using those two pieces of information,
# this script generates a new package version Id per unique Action run, and promotes that package on merges to main
# it also updates the Ids referenced in the README, and bumps the package version number in the package.json file
$DebugPreference = 'Continue'
$ErrorActionPreference = 'Stop'
. .\scripts\generatePackage.ps1

function Get-Current-Git-Branch() {
  Invoke-Expression 'git rev-parse --abbrev-ref HEAD'
}

function Start-Package-Promotion {
  Write-Debug "Beginning promote script"

  $allReadmes = Get-ChildItem -Exclude node_modules, .sfdx, tests | Get-ChildItem -Filter README.md -Recurse
  foreach ($readme in $allReadmes) {
    $readmePackageIdResults = (Select-String -Path $readme 'https:\/\/login.salesforce.com\/packaging\/installPackage.apexp\?p0=.{0,18}')
    if ($readmePackageIdResults.Matches.Length -gt 0) {
      $packageIdSplit = $readmePackageIdResults.Matches[0].Value.Split("=")
      if ($packageIdSplit.Length -eq 2) {
        $packageId = $packageIdSplit[1]
        Write-Debug "Promoting $packageId from $readme"
        npx sfdx force:package:version:promote -p $packageId -n
      }
    }
  }
  Write-Debug "Finished package promotion!"
}

# Create/promote package version(s)
$currentBranch = Get-Current-Git-Branch
if ($currentBranch -eq "main") {
  Start-Package-Promotion
} else {
  Generate -packageName "apex-rollup" -readmePath "./README.md"
}
