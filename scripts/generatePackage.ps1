$ErrorActionPreference = 'Stop'

. .\scripts\string-utils.ps1

function Get-SFDX-Project-JSON {
  Get-Content -Path $sfdxProjectJsonPath | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty target-dev-hub
}

$sfdxProjectJsonPath = "./sfdx-project.json"
$sfdxProjectJson = Get-SFDX-Project-JSON
$loggerClassPath = "./rollup/core/classes/RollupLogger.cls"
$shouldGitAddLoggerClass = $true;

function Invoke-Extra-Code-Coverage-Prep() {
  $extraCodeCoveragePath = "./plugins/ExtraCodeCoverage"
  if (Test-Path $extraCodeCoveragePath) {
    Write-Host "Dir exists"
  } else {
    Write-Host "Making ExtraCodeCoverage dir"
    mkdir ./plugins/ExtraCodeCoverage
  }

  Write-Host "Copying rollup tests to gitignored $extraCodeCoveragePath directory"

  $fileNames = "RollupTestUtils","RollupTests","RollupEvaluatorTests","RollupFlowTests","RollupRelationshipFieldFinderTests","RollupLoggerTests","RollupQueryBuilderTests","RollupRecursionItemTests"
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
  Write-Host "Updating $filePath with new package version Id ..." -ForegroundColor Yellow
  $loginReplacement = "https://login.salesforce.com/packaging/installPackage.apexp?p0=" + $newPackageVersionId
  $testReplacement = "https://test.salesforce.com/packaging/installPackage.apexp?p0=" + $newPackageVersionId
  ((Get-Content -path $filePath -Raw) -replace "https:\/\/login.salesforce.com\/packaging\/installPackage.apexp\?p0=.{0,18}", $loginReplacement) | Set-Content -Path $filePath -NoNewline
  ((Get-Content -path $filePath -Raw) -replace "https:\/\/test.salesforce.com\/packaging\/installPackage.apexp\?p0=.{0,18}", $testReplacement) | Set-Content -Path $filePath -NoNewline
  git add $filePath -f
}

function Get-Is-Version-Promoted {
  param ($versionNumber, $packageName)
  $promotedPackageVersions = (npx sf package version list --released --packages $packageName --json | ConvertFrom-Json).result | Select-Object -ExpandProperty Version

  if ($null -eq $promotedPackageVersions) {
    return $false
  } else {
    $isPackagePromoted = $promotedPackageVersions.Contains($versionNumber)
    Write-Host "Is $versionNumber for $packageName promoted? $isPackagePromoted" -ForegroundColor Yellow
    return $isPackagePromoted
  }
}

function Get-Package-JSON {
  Get-Content -Path ./package.json | ConvertFrom-Json
}

function Update-Logger-Class {
  param (
      $versionNumber
  )
  $versionNumber = "v" + $versionNumber
  Write-Host "Bumping RollupLogger.cls version number to: $versionNumber" -ForegroundColor Yellow

  Find-And-Replace-Content -path $loggerClassPath -searchString "CURRENT_VERSION_NUMBER" -replacement $versionNumber
  npx prettier --write $loggerClassPath
  if ($shouldGitAddLoggerClass -eq $true) {
    git add $loggerClassPath
  }
}

function Update-SFDX-Project-JSON {
  Write-Host "Re-writing sfdx-project.json  ..."
  $content = Get-SFDX-Project-JSON
  Update-SFDX-Project-JSON-With-Content $content
}

function Update-SFDX-Project-JSON-With-Content {
  param ($content)
  ConvertTo-Json -InputObject $content -Depth 4 | Set-Content -Path $sfdxProjectJsonPath -NoNewline
  # sfdx-project.json is ignored by default; use another file as the --ignore-path to force prettier
  # to run on it
  npx prettier --write $sfdxProjectJsonPath --tab-width 4 --ignore-path ..\.forceignore
}

function Get-Next-Package-Version() {
  param ($currentPackage, $packageName)
  $currentPackageVersion = $currentPackage.versionNumber
  $shouldIncrement = Get-Is-Version-Promoted $currentPackageVersion $packageName
  if ($true -eq $shouldIncrement) {
    $currentPackageVersion = $currentPackageVersion.Remove($currentPackageVersion.LastIndexOf(".0"))
    $patchVersionIndex = $currentPackageVersion.LastIndexOf(".");
    $currentVersionNumber = ([int]$currentPackageVersion.Substring($patchVersionIndex + 1, $currentPackageVersion.Length - $patchVersionIndex - 1)) + 1
    Write-Host "Re-incrementing sfdx-project.json version number for $packageName to versionNumber: $currentVersionNumber" -ForegroundColor Yellow
    # increment package version prior to calling SFDX
    $currentPackageVersion = $currentPackageVersion.Substring(0, $patchVersionIndex + 1) + $currentVersionNumber.ToString() + ".0"
    $currentPackage.versionNumber = $currentPackageVersion

    Update-SFDX-Project-JSON-With-Content $sfdxProjectJson
  }
  if ("apex-rollup" -eq $packageName) {
    $versionNumberToWrite = $currentPackageVersion.Remove($currentPackageVersion.LastIndexOf(".0"))
    Update-Logger-Class $versionNumberToWrite
    Write-Host "Bumping package.json version to: $versionNumberToWrite" -ForegroundColor Yellow

    $packageJson = Get-Package-JSON
    $packageJson.version = $versionNumberToWrite
    $packagePath = "./package.json"
    ConvertTo-Json -InputObject $packageJson | Set-Content -Path $packagePath -NoNewline

    git add $packagePath
  }
}

function Get-Package-Directory() {
  param (
    [string]$packageName
  )
  return ($sfdxProjectJson.packageDirectories | Select-Object | Where-Object -Property package -eq $packageName)
}

# used in package.json scripts & build-and-promote-package.ps1
function Generate() {
  param (
    [string]$packageName,
    [string]$readmePath,
    [bool]$shouldCreateNamespacedPackage
  )

  Write-Host "Starting for $packageName" -ForegroundColor Yellow

  if ("Apex Rollup - Extra Code Coverage" -eq $packageName) {
    Invoke-Extra-Code-Coverage-Prep
  }

  $currentPackage = Get-Package-Directory $packageName
  Get-Next-Package-Version $currentPackage $packageName
  $currentPackageVersion = $currentPackage.versionNumber

  Write-Host "Creating package version: $currentPackageVersion ..." -ForegroundColor White

  $stopWatch = [system.diagnostics.stopwatch]::startNew()
  $createPackageResult = npx sf package version create --package $packageName --wait 30 --code-coverage --installation-key-bypass --version-number $currentPackageVersion --json | ConvertFrom-Json
  $stopWatch.Stop()
  Update-SFDX-Project-JSON

  Write-Host "Packaging took: $($stopWatch.Elapsed.TotalMilliseconds) ms" -ForegroundColor White

  $currentPackageVersionId = $createPackageResult.result.SubscriberPackageVersionId
  if ($null -eq $currentPackageVersionId) {
    throw $createPackageResult
  } else {
    npx sf bummer package aliases sort
    git add $sfdxProjectJsonPath -f
  }

  Write-Host "Successfully created package Id: $currentPackageVersionId" -ForegroundColor Green

  Update-Package-Install-Links $readmePath $currentPackageVersionId

  if ($shouldCreateNamespacedPackage -eq $true -and "apex-rollup" -eq $packageName) {
    New-Namespaced-Package
  }

  Write-Host "Finished creating $packageName package version!" -ForegroundColor Green
}

function New-Namespaced-Package {
  Write-Host "Generating namespaced version of package..." -ForegroundColor White

  $originalLoggerClassPath = $loggerClassPath
  $namespacedPackageName = "apex-rollup-namespaced"
  $namespacedProjectJsonPath = "rollup-namespaced/sfdx-project.json"
  $originalProjectJsonBackupPath = "./sfdx-project-original.json"
  $versionName = (Get-Package-Directory "apex-rollup").versionName
  $shouldGitAddLoggerClass = $false
  $loggerClassPath = "rollup-namespaced/source/rollup/core/classes/RollupLogger.cls"
  Write-Host "Logger class path for namespaced package will be added to git: $shouldGitAddLoggerClass"

  Copy-Item $sfdxProjectJsonPath $originalProjectJsonBackupPath -Force
  Copy-Item $namespacedProjectJsonPath $sfdxProjectJsonPath -Force
  Copy-Item -Path ./extra-tests -Destination rollup-namespaced/source/extra-tests -Recurse -Force
  Copy-Item -Path ./rollup -Destination rollup-namespaced/source/rollup -Recurse -Force
  # the class names in a test suite need to have the namespace be appended, which is a waste here
  # since we aren't using the test suite for anything except local development & testing
  Remove-Item -Path ./rollup-namespaced/source/extra-tests/testSuites -Recurse -Force

  # we always want to stay in lock-step with the current versionName between the non-namespace and namespaced versions of the package
  $sfdxProjectJson = Get-SFDX-Project-JSON
  $namespacedPackageDirectory = Get-Package-Directory $namespacedPackageName
  $namespacedPackageDirectory.versionName = $versionName
  $sfdxProjectJson.packageDirectories[0].versionName = $versionName
  Update-SFDX-Project-JSON-With-Content $sfdxProjectJson

  # now that the version name's been copied over, we're good to generate
  try {
    Generate $namespacedPackageName "rollup-namespaced/README.md" $false
  } catch {
    Write-Host "An error occurred during package generation:" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
  }

  Copy-Item $sfdxProjectJsonPath $namespacedProjectJsonPath -Force
  Copy-Item $originalProjectJsonBackupPath $sfdxProjectJsonPath -Force
  Remove-Item $originalProjectJsonBackupPath

  git add $sfdxProjectJsonPath -f
  git add $namespacedProjectJsonPath -f
  Remove-Item -Path rollup-namespaced/source -Recurse -Force
  $shouldGitAddLoggerClass = $true
  $loggerClassPath = $originalLoggerClassPath
}
