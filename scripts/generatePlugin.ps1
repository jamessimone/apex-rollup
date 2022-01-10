$DebugPreference = 'Continue'
$ErrorActionPreference = 'Stop'
. .\scripts\helper-functions.ps1

$packageJsonPath = "./sfdx-project.json"
$packageJson = Get-SFDX-Project-JSON

function Invoke-Extra-Code-Coverage-Prep() {
  $extraCodeCoveragePath = "./plugins/ExtraCodeCoverage"
  if (Test-Path $extraCodeCoveragePath) {
    Write-Debug "Dir exists"
  } else {
    Write-Debug "Making ExtraCodeCoverage dir"
    mkdir ./plugins/ExtraCodeCoverage
  }

  Write-Debug "Copying rollup tests to gitignored $extraCodeCoveragePath directory"

  $fileNames = "RollupTestUtils","RollupTests","RollupEvaluatorTests","RollupRelationshipFieldFinderTests","RollupLoggerTests","RollupQueryBuilderTests","RollupRecursionItemTests"
  foreach ($fileName in $fileNames) {
    Copy-Item "extra-tests/classes/$fileName.cls" $extraCodeCoveragePath
    Copy-Item "extra-tests/classes/$fileName.cls-meta.xml" $extraCodeCoveragePath
  }
}

# used in package.json scripts
function Generate() {
  param (
    $packageName,
    $readmePath
  )

  Write-Debug "Starting up for $packageName"

  if ("Apex Rollup - Extra Code Coverage" -eq $packageName) {
    Invoke-Extra-Code-Coverage-Prep
  }

  $currentCodeCoveragePlugin = ($packageJson.packageDirectories | Select-Object | ?{ $_.package -eq $packageName })
  $currentPluginVersion = $currentCodeCoveragePlugin.versionNumber
  $currentPluginVersion = $currentPluginVersion.Remove($currentPluginVersion.LastIndexOf(".0"))
  # increment package version prior to calling SFDX
  $currentVersionNumber = ([int]$currentPluginVersion.Substring(4)) + 1
  $currentPluginVersion = "0.0." + $currentVersionNumber.ToString() + ".0"
  $currentCodeCoveragePlugin.versionNumber = $currentPluginVersion

  Write-Debug "Re-incrementing sfdx-project.json version number for $packageName ..."

  ConvertTo-Json -InputObject $packageJson -Depth 4 | Set-Content -Path $packageJsonPath -NoNewline
  # sfdx-project.json is ignored by default; use another file as the --ignore-path to force prettier
  # to run on it
  yarn prettier --write $packageJsonPath --tab-width 4 --ignore-path .forceignore

  Write-Debug "Creating package version: $currentPluginVersion"

  $createPackageResult = sfdx force:package:version:create -p $packageName -w 30 -c -x -n $currentPluginVersion --json | ConvertFrom-Json
  Write-Debug $createPackageResult
  $currentPackageVersionId = $createPackageResult.result.SubscriberPackageVersionId
  if ($null -eq $currentPackageVersionId) {
    throw $createPackageResult
  }

  Write-Debug "Successfully created package Id: $currentPackageVersionId"

  Update-Package-Install-Links $readmePath $currentPackageVersionId

  git add $packageJsonPath

  Write-Debug "Done"
}
