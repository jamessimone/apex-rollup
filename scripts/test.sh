#!/usr/bin/env bash

# The script assumes you've `jq` installed in addition to `sfdx`

echo "Starting build script"

orgInfo=$(sf org display --json --verbose 2>/dev/null)
userNameHasBeenSet=0

if [ -f "./DEVHUB_SFDX_URL.txt" ]; then
  echo "Auth file exists"
else
  echo "creating auth file"
  echo $orgInfo | jq -r '.result.sfdxAuthUrl' > ./DEVHUB_SFDX_URL.txt
fi

# Authorize Dev Hub using prior creds. There's some issue with the flags --setdefaultdevhubusername and --setdefaultusername both being passed when run remotely

sf org login sfdx-url --sfdx-url-file ./DEVHUB_SFDX_URL.txt --alias apex-rollup
sf config set target-org james@sheandjim.com target-dev-hub james@sheandjim.com

# For local dev, store currently auth'd org to return to
# Also store test command shared between script branches, below
scratchOrgAllotment=$(sf org list limits 2>/dev/null --json | jq -r '.result[] | select (.name=="DailyScratchOrgs").remaining')

echo "Total remaining scratch orgs for the day: $scratchOrgAllotment"
testInvocation='sf apex run test --code-coverage --output-dir ./tests/apex --result-format human --wait 20'
echo "Test command to use: $testInvocation"

if [ $scratchOrgAllotment -gt 0 ]; then
  echo "Beginning scratch org creation"
  userNameHasBeenSet=1
  {
    npm run create:org
    # Deploy
    sf project deploy start
    # Run tests
    echo "Starting test run ..."
    $testInvocation
    echo "Scratch org tests finished running with success: $?"
    # Delete scratch org
    sf org delete scratch --no-prompt --target-org apex-rollup-scratch-org
  } || {
    echo "there was a problem with scratch org creation. continuing..."
  }
else
  echo "No scratch orgs remaining, running tests on sandbox"
  # Deploy
  sf project deploy start --source-dir rollup
  # Run tests
  $testInvocation
  echo "Tests finished running with success: $?"

fi

# If the priorUserName is not blank and we used a scratch org, reset to it
if [ "$(echo $orgInfo | jq -r '.result.username' 2>/dev/null)" != "" ] && [ $userNameHasBeenSet -gt 0 ]; then
  priorUserName=$(echo $orgInfo | jq -r '.result.username')
  echo "Resetting SFDX to previously authorized org"
  sf config set target-org $priorUserName
fi

echo "Resetting SFDX project JSON at project root"
cp ./scripts/sfdx-project.json ./sfdx-project.json
rm ./scripts/sfdx-project.json

echo "Build + testing finished successfully, preparing to upload code coverage"
