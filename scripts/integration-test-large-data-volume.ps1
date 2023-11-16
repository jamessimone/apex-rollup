$ErrorActionPreference = 'Stop'

. .\scripts\string-utils.ps1

$pendingStatus = "PENDING"
$batchScriptPath = "scripts/start-and-return-batch-status.apex"
$desiredIntegrationSumAmount = 0
$desiredRecordCountPerIteration = 8000
$desiredIterations = 10

function Get-Expected-Annual-Revenue() {
  param(
    $iterationCount,
    $sumAmount
  )
  if ($iterationCount -lt $desiredIterations) {
    $currentOffset = $desiredRecordCountPerIteration * $iterationCount
    $startingOffset = $currentOffset
    for ($currentOffset; $currentOffset -lt ($startingOffset + $desiredRecordCountPerIteration); $currentOffset++) {
      $sumAmount += $currentOffset
    }
    $iterationCount++
    $sumAmount = Get-Expected-Annual-Revenue $iterationCount $sumAmount
  }
  return $sumAmount
}

function Get-SFDX-Batch-Status() {
  param($scriptPath, $sleepSeconds)
  $sfdxResponse = (npx sf apex run --file $scriptPath --json) | Join-String
  Write-Host $sfdxResponse
  $responseObject = ConvertFrom-Json -InputObject $sfdxResponse -Depth 2
  if ($responseObject.result.success -eq $false) {
    throw "An error occurred!"
  }
  $responseLog = $responseObject.result.logs
  $debugMatches = $responseLog.Split('|DEBUG|');
  Write-Host "Incoming debug matches ..."
  foreach ($debugMatch in $debugMatches) {
    Write-Host $debugMatch
  }
  # assume last debug message is always the "response"
  $debugMatches = $debugMatches[$debugMatches.Length - 1] | Select-String -Pattern "\A.*";
  $responseStatus = $debugMatches.Matches[0].Value;
  Write-Host "Batch status from SFDX: $responseStatus"
  while ($responseStatus -eq $pendingStatus) {
    Write-Host "Sleeping for $sleepSeconds seconds ..."
    Start-Sleep -Seconds $sleepSeconds
    $responseStatus = Get-SFDX-Batch-Status $scriptPath $sleepSeconds
  }
  return $responseStatus
}

function Set-Proper-Script-Variables() {
  $firstLine = Get-Content -Path $batchScriptPath -TotalCount 1
  $localReplacementString = "INSERT_UTC_TIME_IN_SECONDS_HERE"
  $desiredAnnualRevenueValue = "0"
  if($firstLine -eq "String SCRIPT_VAR_1 = '$localReplacementString';") {
    $utcMillis = Get-Date -UFormat %s
    Write-Host "Writing current time into script: $utcMillis"
    $localReplacementString = $utcMillis
    $desiredAnnualRevenueValue = $desiredIntegrationSumAmount
  }
  Find-And-Replace-Content -path $batchScriptPath -searchString "SCRIPT_VAR_1" -replacement $localReplacementString
  Find-And-Replace-Content -path $batchScriptPath -searchString "SCRIPT_VAR_2" -replacement $desiredAnnualRevenueValue
}

function Start-Opportunity-Creation() {
  Write-Host "Populating records if necessary ..."
  $path = "scripts/record-creation-one-parent-many-children.apex"
  Find-And-Replace-Content -path $path -searchString "SCRIPT_VAR_1" -replacement "sForce"
  Find-And-Replace-Content -path $path -searchString "SCRIPT_VAR_2" -replacement $desiredRecordCountPerIteration
  Find-And-Replace-Content -path $path -searchString "SCRIPT_VAR_3" -replacement $desiredIterations
  Get-SFDX-Batch-Status $path 1
}

function Start-Integration-Tests() {
  $desiredIntegrationSumAmount = Get-Expected-Annual-Revenue 0 $desiredIntegrationSumAmount
  Write-Output "Expected sum amount ends up as: $desiredIntegrationSumAmount"

  Start-Opportunity-Creation

  Write-Host "Beginning integration testing for script $batchScriptPath ..."
  Set-Proper-Script-Variables
  Get-SFDX-Batch-Status $batchScriptPath 30
  # reset batch file
  Set-Proper-Script-Variables
}

