$ErrorActionPreference = 'Stop'
. .\scripts\helper-functions.ps1

$packageJsonPath = "./sfdx-project.json"

if (Test-Path "./plugins/ExtraCodeCoverage" ) {
  Write-Output "Dir exists"
} else {
  Write-Output "Making ExtraCodeCoverage dir"
  mkdir ./plugins/ExtraCodeCoverage
}

Write-Output "Copying rollup tests to gitignored plugins/ExtraCodeCoverage directory"

$fileNames = "RollupTestUtils","RollupTests","RollupEvaluatorTests","RollupRelationshipFieldFinderTests","RollupLoggerTests","RollupQueryBuilderTests","RollupRecursionItemTests"
foreach ($fileName in $fileNames) {
  Copy-Item "extra-tests/classes/$fileName.cls" "plugins/ExtraCodeCoverage"
  Copy-Item "extra-tests/classes/$fileName.cls-meta.xml" "plugins/ExtraCodeCoverage"
}

$packageJson = Get-SFDX-Project-JSON
$currentCodeCoveragePlugin = ($packageJson.packageDirectories | Select-Object | ?{ $_.package -eq "Apex Rollup - Extra Code Coverage" })
$currentPluginVersion = $currentCodeCoveragePlugin.versionNumber
$currentPluginVersion = $currentPluginVersion.Remove($currentPluginVersion.LastIndexOf(".0"))
# increment package version prior to calling SFDX
$currentVersionNumber = ([int]$currentPluginVersion.Substring(4)) + 1
$currentPluginVersion = "0.0." + $currentVersionNumber.ToString() + ".0"
$currentCodeCoveragePlugin.versionNumber = $currentPluginVersion

Write-Output "Re-incrementing sfdx-project.json ExtraCodeCoverage version number ..."

ConvertTo-Json -InputObject $packageJson -Depth 4 | Set-Content -Path $packageJsonPath -NoNewline
# sfdx-project.json is ignored by default; use another file as the --ignore-path to force prettier
# to run on it
yarn prettier --write $packageJsonPath --tab-width 4 --ignore-path .forceignore

Write-Output "Creating package version: $currentPluginVersion"

$createPackageResult = sfdx force:package:version:create -p "Apex Rollup - Extra Code Coverage" -w 30 -c -x -n $currentPluginVersion --json | ConvertFrom-Json
Write-Output $createPackageResult
$currentPackageVersionId = $createPackageResult.result.SubscriberPackageVersionId

Write-Output "Successfully created package Id: $currentPackageVersionId, promoting ..."
sfdx force:package:version:promote -p $currentPackageVersionId -n

Update-Package-Install-Links "./plugins/ExtraCodeCoverage/README.md" $currentPackageVersionId

git add $packageJsonPath

Write-Output "Done"