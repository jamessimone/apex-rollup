$ErrorActionPreference = 'Stop'

$packageJsonPath = "./sfdx-project.json"
function Get-SFDX-Project-JSON {
  Get-Content -Path $packageJsonPath | ConvertFrom-Json
}

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
yarn prettier --write $packageJsonPath --tab-width 4 --ignore-path .forceignore

Write-Output "Creating package version: $currentPluginVersion"

$createPackageResult = sfdx force:package:version:create -p "Apex Rollup - Extra Code Coverage" -w 30 -c -x -n $currentPluginVersion --json | ConvertFrom-Json
Write-Output $createPackageResult
$currentPackageVersionId = $createPackageResult.result.SubscriberPackageVersionId

Write-Output "Successfully created package Id: $currentPackageVersionId, promoting ..."
sdfx force:package:version:promote -p $currentPackageVersionId -n

$readmePath = "./plugins/ExtraCodeCoverage/README.md"
$loginReplacement = "https://login.salesforce.com/packaging/installPackage.apexp?p0=" + $currentPackageVersionId
$testReplacement = "https://test.salesforce.com/packaging/installPackage.apexp?p0=" + $currentPackageVersionId
((Get-Content -path $readmePath -Raw) -replace "https:\/\/login.salesforce.com\/packaging\/installPackage.apexp\?p0=.{0,18}", $loginReplacement) | Set-Content -Path $readmePath -NoNewline
((Get-Content -path $readmePath -Raw) -replace "https:\/\/test.salesforce.com\/packaging\/installPackage.apexp\?p0=.{0,18}", $testReplacement) | Set-Content -Path $readmePath -NoNewline

# have to force add, as the rest of the dir is gitignored
git add $readmePath -f
git add $packageJsonPath

Write-Output "Done"