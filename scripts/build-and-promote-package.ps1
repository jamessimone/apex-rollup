# This script is invoked by the Github Action on pull requests / merges to main
# It relies on the versionNumber being set manually in your sfdx-project.json:
# the versionDescription and versionNumber for the default package. Using that,
# this script generates a new package version Id per unique Action run, and promotes that package on merges to main
# it also updates the Ids referenced in the README, bumps the package version number in the package.json file, and
# tags the release on merges to main
$DebugPreference = 'Continue'
$ErrorActionPreference = 'Stop'
. .\scripts\generatePackage.ps1
. .\scripts\string-utils.ps1

function Push-Git-Tag() {
  $tagMatches = (Invoke-Expression "git log -n 1" | Select-String -Pattern "V\d+.\d+.\d+")
  if ($tagMatches.Matches.Length -eq 1) {
    $tag = $tagMatches.Matches[0].Value.ToLower()
    git tag $tag
    git push origin $tag -f
    Write-Host "Created $tag tag and pushed to git"
  }
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
        npx sf package version promote --package $packageId --no-prompt
      }
    }
  }
  Write-Debug "Finished package promotion!"
}

# Create/promote package version(s)
$currentBranch = Get-Current-Git-Branch
if ($currentBranch -eq "main") {
  Start-Package-Promotion
  Push-Git-Tag
} else {
  Generate -packageName "apex-rollup" -readmePath "./README.md" -shouldCreateNamespacedPackage $true
}
