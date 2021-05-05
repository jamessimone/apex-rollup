# This script is invoked by the Github Action on pull requests / merges to main
# It relies on two pieces of information being set manually in your sfdx-project.json:
# the versionDescription and versionNumber for the default package. Using those two pieces of information,
# this script generates a new package version Id per unique Action run, and promotes that package on merges to main
# it also updates the Ids referenced in the README, and bumps the package version number in the package.json file
$ErrorActionPreference = 'Stop'

function Get-Current-Git-Branch() {
  Invoke-Expression 'git rev-parse --abbrev-ref HEAD'
}

function Get-Apex-Rollup-Package-Alias {
  param (
    $packageVersion
  )
  return "apex-rollup@$packageVersion-0"
}

function Get-SFDX-Project-JSON {
  Get-Content -Path ./sfdx-project.json | ConvertFrom-Json
}

function Get-Package-JSON {
  Get-Content -Path ./package.json | ConvertFrom-Json
}

function Update-Last-Substring {
  param(
      [string]$str,
      [string]$substr,
      [string]$newstr
  )

  return $str.Remove(($lastIndex = $str.LastIndexOf($substr)),$substr.Length).Insert($lastIndex,$newstr)
}

if(Test-Path ".\PACKAGING_SFDX_URL.txt") {
  sfdx auth:sfdxurl:store -f ./PACKAGING_SFDX_URL.txt -a packaging-org
  sfdx force:config:set defaultdevhubusername=packaging-org
} else {
  throw 'No packaging auth info!'
}

$sfdxProjectJson = Get-SFDX-Project-JSON
$currentPackageVersion = $sfdxProjectJson.packageDirectories.versionNumber

Write-Output "Current package version number: $currentPackageVersion"

# Cache the prior package version Id to replace in the README
$priorPackageVersionId = $null
$priorPackageVersionNumber = $null;
try {
  $priorPackageVersionNumber = $currentPackageVersion.Trim(".0")
  $priorPackageVersionId = $sfdxProjectJson.packageAliases | Select-Object -ExpandProperty (Get-Apex-Rollup-Package-Alias $priorPackageVersionNumber)
} catch {
  # if there hasn't been a current version of the package, get the previous version and its associated package Id
  $currentPackageNumber = ([int]($currentPackageVersion | Select-String -Pattern \S\S.0).Matches.Value)
  $currentPackageNumberString = $currentPackageNumber.ToString()
  $priorPackageVersionString = ($currentPackageNumber - 1).ToString()
  $priorPackageVersionNumber = (Update-Last-Substring $currentPackageVersion $currentPackageNumberString $priorPackageVersionString).Trim(".0")

  $priorPackageVersionId = $sfdxProjectJson.packageAliases | Select-Object -ExpandProperty (Get-Apex-Rollup-Package-Alias $priorPackageVersionNumber)
}

Write-Output "Prior package version: $priorPackageVersionId"
Write-Output "Prior package version number: $priorPackageVersionNumber"

# Create package version

Write-Output "Creating new package version"

$packageVersionNotes = $sfdxProjectJson.packageDirectories.versionDescription
sfdx force:package:version:create -d rollup -x -w 10 -e $packageVersionNotes -c --releasenotesurl $sfdxProjectJson.packageDirectories.releaseNotesUrl

# Now that sfdx-project.json has been updated, grab the latest package version
$currentPackageVersionId = $null
try {
  $currentPackageVersionId = (Get-SFDX-Project-JSON).packageAliases | Select-Object -ExpandProperty (Get-Apex-Rollup-Package-Alias $currentPackageVersion.Trim(".0"))
} catch {
  $currentPackageVersionId = (Get-SFDX-Project-JSON).packageAliases | Select-Object -ExpandProperty (Get-Apex-Rollup-Package-Alias $priorPackageVersionNumber)
}

Write-Output "New package version: $currentPackageVersionId"

if($currentPackageVersionId -ne $priorPackageVersionId) {
  $readmePath = "./README.md"
  ((Get-Content -path $readmePath -Raw) -replace $priorPackageVersionId, $currentPackageVersionId) | Set-Content -Path $readmePath -NoNewline

  git add $readmePath
}

$packageJson = Get-Package-JSON
if ($packageJson.version -ne $currentPackageVersion) {
  Write-Output "Bumping package.json version to: $currentPackageVersion"

  $packageJson.version = $currentPackageVersion
  $packagePath = "./package.json"
  ConvertTo-Json -InputObject $packageJson | Set-Content -Path $packagePath -NoNewline

  git add $packagePath
}

# promote package on merge to main
$currentBranch = Get-Current-Git-Branch
if($currentBranch -eq "main") {
  Write-Output "Promoting package version"
  sfdx force:package:version:promote -p $currentPackageVersionId -n
}

git add ./sfdx-project.json

git config --global user.name "James Simone"
git config --global user.email "16430727+jamessimone@users.noreply.github.com"
git remote set-url --push origin https://jamessimone:$GITHUB_TOKEN@github.com/jamessimone/apex-rollup

git commit -m "Bumping package version from Github Action"
git push