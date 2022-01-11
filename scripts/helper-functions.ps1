$DebugPreference = 'Continue'
$ErrorActionPreference = 'Stop'

function Get-SFDX-Project-JSON {
  Get-Content -Path ./sfdx-project.json | ConvertFrom-Json
}

function Update-Package-Install-Links {
  param (
    $filePath,
    $newPackageVersionId
  )

  $loginReplacement = "https://login.salesforce.com/packaging/installPackage.apexp?p0=" + $newPackageVersionId
  $testReplacement = "https://test.salesforce.com/packaging/installPackage.apexp?p0=" + $newPackageVersionId
  ((Get-Content -path $filePath -Raw) -replace "https:\/\/login.salesforce.com\/packaging\/installPackage.apexp\?p0=.{0,18}", $loginReplacement) | Set-Content -Path $filePath -NoNewline
  ((Get-Content -path $filePath -Raw) -replace "https:\/\/test.salesforce.com\/packaging\/installPackage.apexp\?p0=.{0,18}", $testReplacement) | Set-Content -Path $filePath -NoNewline
  git add $filePath -f
}

function Start-Package-Promotion {
  Write-Debug "Beginning promote script"

  $allReadmes = Get-ChildItem -Exclude node_modules, .sfdx, tests | Get-ChildItem -Filter README.md -Recurse
  foreach ($readme in $allReadmes) {
    $readmePackageIdResults = (Select-String -Path $readme 'https:\/\/login.salesforce.com\/packaging\/installPackage.apexp\?p0=.{0,18}')
    if ($readmePackageIdResults.Matches.Length -gt 0) {
      $packageIdSplit = $readmePackageId.Matches[0].Value.Split("=")
      if ($packageIdSplit.Length -eq 2) {
        $packageId = $packageIdSplit[1]
        Write-Debug "Promoting $packageId from $readme"
        npx sfdx force:package:version:promote -p $packageId -n
      }
    }
  }
  Write-Debug "Finished package promotion!"
}

function Get-Is-Version-Promoted {
  param ($versionNumber, $packageName)
  return ((sfdx force:package:version:list --released --packages $packageName --json | ConvertFrom-Json).result | Select-Object -Property Version).Contains($versionNumber)
}