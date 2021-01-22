
# This is also the same script that runs on Github via the Github Action configured in .github/workflows - there, the
# DEVHUB_SFDX_URL.txt file is populated in a build step

Write-Output "Starting build script"

$orgInfo = sfdx force:org:display --json --verbose | ConvertFrom-Json
$userNameHasBeenSet = $false
if(Test-Path ".\DEVHUB_SFDX_URL.txt") {
  Write-Output "Auth file already exists, continuing"
} else {
  $orgInfo.result.sfdxAuthUrl | Out-File -FilePath ".\DEVHUB_SFDX_URL.txt"
}

# Authorize Dev Hub using prior creds. There's some issue with the flags --setdefaultdevhubusername and --setdefaultusername both being passed when run remotely

sfdx force:auth:sfdxurl:store -f ./DEVHUB_SFDX_URL.txt -a apex-rollup
sfdx config:set defaultusername=james@sheandjim.com defaultdevhubusername=james@sheandjim.com

# For local dev, store currently auth'd org to return to
# Also store test command shared between script branches, below
$scratchOrgAllotment = ((sfdx force:limits:api:display --json | ConvertFrom-Json).result | Where-Object -Property name -eq "DailyScratchOrgs").remaining
Write-Output "Total remaining scratch orgs for the day: $scratchOrgAllotment"
$testInvocation = 'sfdx force:apex:test:run -n "RollupTests, RollupEvaluatorTests" -r human -w 20'
Write-Output "Test command to use: $testInvocation"

if($scratchOrgAllotment -gt 0) {
  Write-Output "Beginning scratch org creation"
  $userNameHasBeenSet = $true
  # Create Scratch Org
  try {
  sfdx force:org:create -f config/project-scratch-def.json -a apex-rollup-scratch-org -s -d 1
  # Deploy
  sfdx force:source:push
  # Run tests
  Invoke-Expression $testInvocation
  Write-Output "Scratch org tests finished running with success: $?"
  # Delete scratch org
  sfdx force:org:delete -p -u apex-rollup-scratch-org
  } catch {
    Write-Output "There was an issue with scratch org creation, continuing ..."
  }
} else {
  Write-Output "No scratch orgs remaining, running tests on sandbox"

  # Deploy
  sfdx force:source:deploy -p rollup
  # Run tests
  Invoke-Expression $testInvocation
  Write-Output "Tests finished running with success: $?"
}

# If the priorUserName is not blank and we used a scratch org, reset to it
if($orgInfo.result.username -And $userNameHasBeenSet) {
  # for some reason, setting straight from $orgInfo.result.username results in some weird destructuring
  # whereas this works, no problem
  $priorUserName = $orgInfo.result.username
  Write-Output "Resetting SFDX to previously authorized org"
  sfdx force:config:set defaultusername=$priorUserName
}

Write-Output "Build + testing finished successfully"