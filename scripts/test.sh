#!/usr/bin/env bash

# The script assumes you've `jq` installed in addition to `sfdx`

echo "Starting build script"

orgInfo=$(sfdx force:org:display --json --verbose 2>/dev/null)
userNameHasBeenSet=0

if [ -f "./DEVHUB_SFDX_URL.txt" ]; then
  echo "Auth file exists"
else
  echo "creating auth file"
  echo $orgInfo | jq -r '.result.sfdxAuthUrl' > ./DEVHUB_SFDX_URL.txt
fi

echo "Copying deploy SFDX project json file to root directory, storing backup in /scripts"
cp ./sfdx-project.json ./scripts/sfdx-project.json
cp ./scripts/deploy-sfdx-project.json ./sfdx-project.json

# Authorize Dev Hub using prior creds. There's some issue with the flags --setdefaultdevhubusername and --setdefaultusername both being passed when run remotely

sfdx auth:sfdxurl:store -f ./DEVHUB_SFDX_URL.txt -a apex-rollup
sfdx config:set defaultusername=james@sheandjim.com defaultdevhubusername=james@sheandjim.com

# For local dev, store currently auth'd org to return to
# Also store test command shared between script branches, below
scratchOrgAllotment=$(sfdx force:limits:api:display 2>/dev/null --json | jq -r '.result[] | select (.name=="DailyScratchOrgs").remaining')
echo "Total remaining scratch orgs for the day: $scratchOrgAllotment"
testInvocation='sfdx force:apex:test:run -c -d ./tests/apex -r human -w 20'
echo "Test command to use: $testInvocation"

if [ $scratchOrgAllotment -gt 0 ]; then
  echo "Beginning scratch org creation"
  userNameHasBeenSet=1
  {
    sfdx force:org:create -f config/project-scratch-def.json -a apex-rollup-scratch-org -s -d 1
    # Deploy
    sfdx force:source:push
    # Run tests
    echo "Starting test run ..."
    $testInvocation
    echo "Scratch org tests finished running with success: $?"
    # Delete scratch org
    sfdx force:org:delete -p -u apex-rollup-scratch-org
  } || {
    echo "there was a problem with scratch org creation. continuing..."
  }
else
  echo "No scratch orgs remaining, running tests on sandbox"
  # Deploy
  sfdx force:source:deploy -p rollup
  # Run tests
  $testInvocation
  echo "Tests finished running with success: $?"

fi

# If the priorUserName is not blank and we used a scratch org, reset to it
if [ "$(echo $orgInfo | jq -r '.result.username' 2>/dev/null)" != "" ] && [ $userNameHasBeenSet -gt 0 ]; then
  priorUserName=$(echo $orgInfo | jq -r '.result.username')
  echo "Resetting SFDX to previously authorized org"
  sfdx force:config:set defaultusername=$priorUserName
fi

echo "Resetting SFDX project JSON at project root"
cp ./scripts/sfdx-project.json ./sfdx-project.json
rm ./scripts/sfdx-project.json

echo "Build + testing finished successfully, preparing to upload code coverage"
