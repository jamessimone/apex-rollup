$DebugPreference = 'Continue'
$ErrorActionPreference = 'Stop'


function Get-SFDX-Project-JSON {
  Get-Content -Path ./sfdx-project.json | ConvertFrom-Json
}

$sfdxProjectJsonPath = "./sfdx-project.json"
$sfdxProjectJson = Get-SFDX-Project-JSON
$loggerClassPath = "./rollup/core/classes/RollupLogger.cls"

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

function Update-Package-Install-Links {
  param (
    $filePath,
    $newPackageVersionId
  )
  Write-Debug "Updating $filePath with new package version Id ..."
  $loginReplacement = "https://login.salesforce.com/packaging/installPackage.apexp?p0=" + $newPackageVersionId
  $testReplacement = "https://test.salesforce.com/packaging/installPackage.apexp?p0=" + $newPackageVersionId
  ((Get-Content -path $filePath -Raw) -replace "https:\/\/login.salesforce.com\/packaging\/installPackage.apexp\?p0=.{0,18}", $loginReplacement) | Set-Content -Path $filePath -NoNewline
  ((Get-Content -path $filePath -Raw) -replace "https:\/\/test.salesforce.com\/packaging\/installPackage.apexp\?p0=.{0,18}", $testReplacement) | Set-Content -Path $filePath -NoNewline
  git add $filePath -f
}


function Get-Is-Version-Promoted {
  param ($versionNumber, $packageName)
  $promotedPackageVersions = (sfdx force:package:version:list --released --packages $packageName --json | ConvertFrom-Json).result | Select-Object -ExpandProperty Version
  $isPackagePromoted = $promotedPackageVersions.Contains($versionNumber)
  Write-Debug "Is $versionNumber for $packageName promoted? $isPackagePromoted"
  return $isPackagePromoted
}

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

function Get-Next-Package-Version() {
  param ($currentPackage, $packageName)
  $currentPackageVersion = $currentPackage.versionNumber
  $shouldIncrement = Get-Is-Version-Promoted $currentPackageVersion $packageName
  if ($true -eq $shouldIncrement) {
    $currentPackageVersion = $currentPackageVersion.Remove($currentPackageVersion.LastIndexOf(".0"))
    $patchVersionIndex = $currentPackageVersion.LastIndexOf(".");
    $currentVersionNumber = ([int]$currentPackageVersion.Substring($patchVersionIndex + 1, $currentPackageVersion.Length - $patchVersionIndex - 1)) + 1
    Write-Debug "Re-incrementing sfdx-project.json version number for $packageName to versionNumber: $currentVersionNumber"
    # increment package version prior to calling SFDX
    $currentPackageVersion = $currentPackageVersion.Substring(0, $patchVersionIndex + 1) + $currentVersionNumber.ToString() + ".0"
    $currentPackage.versionNumber = $currentPackageVersion

    Write-Debug "Re-writing sfdx-project.json with updated package version number ..."
    ConvertTo-Json -InputObject $sfdxProjectJson -Depth 4 | Set-Content -Path $sfdxProjectJsonPath -NoNewline
    # sfdx-project.json is ignored by default; use another file as the --ignore-path to force prettier
    # to run on it
    npx run prettier --write $sfdxProjectJsonPath --tab-width 4 --ignore-path .forceignore
  }
  if ("apex-rollup" -eq $packageName) {
    $versionNumberToWrite = $currentPackageVersion.Remove($currentPackageVersion.LastIndexOf(".0"))
    Update-Logger-Class $versionNumberToWrite
    Write-Debug "Bumping package.json version to: $versionNumberToWrite"

    $packageJson = Get-Package-JSON
    $packageJson.version = $versionNumberToWrite
    $packagePath = "./package.json"
    ConvertTo-Json -InputObject $packageJson | Set-Content -Path $packagePath -NoNewline

    git add $packagePath
  }
}

# used in package.json scripts & build-and-promote-package.ps1
function Generate() {
  param (
    [string]$packageName,
    [string]$readmePath
  )

  Write-Debug "Starting for $packageName"

  if ("Apex Rollup - Extra Code Coverage" -eq $packageName) {
    Invoke-Extra-Code-Coverage-Prep
  }

  $currentPackage = ($sfdxProjectJson.packageDirectories | Select-Object | Where-Object -Property package -eq $packageName)
  Get-Next-Package-Version $currentPackage $packageName
  $currentPackageVersion = $currentPackage.versionNumber
  $currentPackageName = $currentPackage.versionName

  Write-Debug "Creating package version: $currentPackageVersion"

  $createPackageResult = sfdx force:package:version:create -p $packageName -w 30 -c -x -n $currentPackageVersion -a $currentPackageName --json | ConvertFrom-Json
  $currentPackageVersionId = $createPackageResult.result.SubscriberPackageVersionId
  if ($null -eq $currentPackageVersionId) {
    throw $createPackageResult
  } else {
    git add $sfdxProjectJsonPath
  }

  Write-Debug "Successfully created package Id: $currentPackageVersionId"

  Update-Package-Install-Links $readmePath $currentPackageVersionId

  Write-Debug "Finished successfully!"
}
