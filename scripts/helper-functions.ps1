function Get-SFDX-Project-JSON {
  Get-Content -Path ./sfdx-project.json | ConvertFrom-Json
}

function Init {
  $DebugPreference = 'Continue'
  $ErrorActionPreference = 'Stop'
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