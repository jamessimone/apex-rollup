# This script is invoked by the Github Action on pull requests / merges to main
# It relies on two pieces of information being set manually in your sfdx-project.json:
# the versionDescription and versionNumber for the default package. Using those two pieces of information,
# this script generates a new package version Id per unique Action run, and promotes that package on merges to main
# it also updates the Ids referenced in the README, and bumps the package version number in the package.json file
. .\scripts\helper-functions.ps1

function Get-Current-Git-Branch() {
  Invoke-Expression 'git rev-parse --abbrev-ref HEAD'
}

function Get-Apex-Rollup-Package-Alias {
  param (
    $packageVersion
  )
  $matchString = ".0-0"
  if ($packageVersion.EndsWith($matchString)) {
    $packageVersion = $packageVersion.Substring(0, $packageVersion.Length - $matchString.Length);
  }
  return "apex-rollup@$packageVersion-0"
}

$loggerClassPath = "./rollup/core/classes/RollupLogger.cls"
function Get-Package-JSON {
  Get-Content -Path ./package.json | ConvertFrom-Json
}

function Get-Logger-Class {
  Get-Content -Raw -Path $loggerClassPath
}

function Update-Logger-Class {
  param (
      $versionNumber
  )
  $versionNumber = "v" + $versionNumber
  $loggerClassContents = Get-Logger-Class
  Write-Debug "Bumping RollupLogger.cls version number to: $versionNumber"

  $targetRegEx = "(.+CURRENT_VERSION_NUMBER = ')(.+)(';)"
  $replacementRegEx = '$1' + $versionNumber + '$3'
  $loggerClassContents -replace $targetRegEx, $replacementRegEx | Set-Content -Path $loggerClassPath -NoNewline
  npx prettier --write $loggerClassPath
  git add $loggerClassPath
}

function Update-Last-Substring {
  param(
      [string]$str,
      [string]$substr,
      [string]$newstr
  )

  return $str.Remove(($lastIndex = $str.LastIndexOf($substr)),$substr.Length).Insert($lastIndex,$newstr)
}

function Get-Latest-Package-Id {
  param(
    $currentPackageVersion,
    $priorPackageVersionNumber
  )
  $currentPackageVersionId = $null
  try {
    $currentPackageVersionId = (Get-SFDX-Project-JSON).packageAliases | Select-Object -ExpandProperty (Get-Apex-Rollup-Package-Alias $currentPackageVersion)
  } catch {
    $currentPackageVersionId = (Get-SFDX-Project-JSON).packageAliases | Select-Object -ExpandProperty (Get-Apex-Rollup-Package-Alias $priorPackageVersionNumber)
  }
  return $currentPackageVersionId
}

Init

if(Test-Path ".\PACKAGING_SFDX_URL.txt") {
  npx sfdx auth:sfdxurl:store -f ./PACKAGING_SFDX_URL.txt -a packaging-org
  npx sfdx force:config:set defaultdevhubusername=packaging-org
} else {
  throw 'No packaging auth info!'
}

$sfdxProjectJson = Get-SFDX-Project-JSON
$currentPackageVersion = $sfdxProjectJson.packageDirectories[0].versionNumber.Remove($sfdxProjectJson.packageDirectories[0].versionNumber.Length - 2, 2)

Write-Debug "Current package version number: $currentPackageVersion"

# Cache the prior package version Id to replace in the README
$priorPackageVersionId = $null
$priorPackageVersionNumber = $null;
try {
  $priorPackageVersionNumber = $currentPackageVersion
  $priorPackageVersionId = $sfdxProjectJson.packageAliases[0] | Select-Object -ExpandProperty (Get-Apex-Rollup-Package-Alias $priorPackageVersionNumber)
} catch {
  # if there hasn't been a current version of the package, get the previous version and its associated package Id
  $currentPackageNumber = ([int]($currentPackageVersion | Select-String -Pattern '(\d|\d\d)$').Matches.Value)
  $currentPackageNumberString = $currentPackageNumber.ToString()
  $priorPackageVersionString = ($currentPackageNumber - 1).ToString()

  $priorPackageVersionNumber = (Update-Last-Substring $currentPackageVersion $currentPackageNumberString $priorPackageVersionString)
  try {
    $priorPackageVersionId = $sfdxProjectJson.packageAliases[0] | Select-Object -ExpandProperty (Get-Apex-Rollup-Package-Alias $priorPackageVersionNumber)
  } catch {
    $allPackages = $sfdxProjectJson.packageAliases[0] | Select-Object -ExcludeProperty 'Nebula Logger*' | Get-Member -MemberType NoteProperty | Select-Object
    $priorPackageVersionFull = $allPackages[$allPackages.Length - 1].Name
    $apexRollupPosition = $priorPackageVersionFull.IndexOf("@")
    $priorPackageVersionId = $priorPackageVersionFull.Substring($apexRollupPosition + 1).Split('-')[0]
    $priorPackageVersionNumber = $priorPackageVersionId
  }
}

Write-Debug "Prior package version: $priorPackageVersionId"
Write-Debug "Prior package version number: $priorPackageVersionNumber"

# Create/promote package version

$currentBranch = Get-Current-Git-Branch
if($currentBranch -eq "main") {
  Write-Debug "Promoting package version"
  $currentPackageVersionId = Get-Latest-Package-Id $currentPackageVersion $priorPackageVersionNumber
  try {
    npx sfdx force:package:version:promote -p $currentPackageVersionId -n
  } catch {
    # Make the assumption that the only reason "promote" would fail is if an unrelated change (like changing this script)
    # triggered a build with an already-promoted package version
  }
} else {
  Update-Logger-Class $currentPackageVersion

  # main is a push-protected branch; only create new package versions as part of PRs against main
  Write-Debug "Creating new package version"

  $packageVersionCreateResult = npx sfdx force:package:version:create -d $sfdxProjectJson.packageDirectories[0].path -x -w 30 -c --json | ConvertFrom-Json
  git add ./sfdx-project.json

  $currentPackageVersionId = $packageVersionCreateResult.result.SubscriberPackageVersionId

  Write-Debug "New package version: $currentPackageVersionId"

  if($currentPackageVersionId -ne $priorPackageVersionId) {
    Update-Package-Install-Links "./README.md" $currentPackageVersionId
  }

  $packageJson = Get-Package-JSON
  if ($packageJson.version -ne $currentPackageVersion) {
    Write-Debug "Bumping package.json version to: $currentPackageVersion"

    $packageJson.version = $currentPackageVersion
    $packagePath = "./package.json"
    ConvertTo-Json -InputObject $packageJson | Set-Content -Path $packagePath -NoNewline

    git add $packagePath
  }
}
