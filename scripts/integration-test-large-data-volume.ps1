$ErrorActionPreference = 'Stop'
$pendingStatus = "PENDING"
$batchScriptPath = "scripts/start-and-return-batch-status.apex"
$initialReplacementString = "INSERT_UTC_TIME_IN_SECONDS_HERE"
$scriptReplacementString = "String SCRIPT_VAR_1 = '$initialReplacementString';"

function Get-SFDX-Batch-Status() {
  param($scriptPath, $sleepSeconds)
  $sfdxResponse = (npx sfdx force:apex:execute -f $scriptPath --json) | Join-String
  $responseObject = ConvertFrom-Json -InputObject $sfdxResponse -Depth 2
  if ($responseObject.result.success -eq $false) {
    throw "An error occurred! $responseObject"
  }
  Write-Host $responseObject
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

function Set-Proper-Datetime() {
  param(
    $replacementString
  )
  $firstLine = Get-Content -Path $batchScriptPath -TotalCount 1
  $localReplacementString = $replacementString
  if($firstLine -eq $replacementString) {
    $utcMillis = (Get-Date -UFormat %s)
    Write-Host "Writing current time into script: $utcMillis"
    $localReplacementString = "String SCRIPT_VAR_1 = '$utcMillis';"
  }
  Write-First-Line-Content $batchScriptPath $localReplacementString
}

function Write-First-Line-Content() {
  param(
    $scriptPath,
    $replacementString
  )
  $firstLine = Get-Content -Path $scriptPath -TotalCount 1
  (Get-Content -Path $scriptPath) |
    ForEach-Object {$_ -Replace $firstLine, $replacementString} |
      Set-Content -Path $scriptPath
}

function Start-Opportunity-Creation() {
  Write-Host "Populating records if necessary ..."
  Get-SFDX-Batch-Status "scripts/record-creation-one-parent-many-children.apex" 1
}

Start-Opportunity-Creation

Write-Host "Beginning integration testing for script $batchScriptPath ..."
Set-Proper-Datetime $scriptReplacementString
Get-SFDX-Batch-Status $batchScriptPath 30
# reset file
Set-Proper-Datetime $scriptReplacementString