#!/usr/bin/bash

set -e
trap 'catch $? $LINENO' EXIT

# Script will throw on line 30 if our scratch org allotment for the day has been exceeded
catch() {
  echo "No scratch orgs remaining, running tests on sandbox"

  # Deploy
  sfdx force:source:deploy -p rollup
  # Run tests
  eval '$testInvocation'
  exit $?
}

echo "Starting build script"

# Authorize Dev Hub
sfdx force:auth:sfdxurl:store -f ./DEVHUB_SFDX_URL.txt -a apex-rollup --setdefaultdevhubusername --setdefaultusername

# For local dev, store currently auth'd org to return to
# Also store test command shared between script branches, below
priorUserName=$(sfdx force:org:display | grep -i 'Alias' | cut -c7- | xargs || "")
echo "Prior username, if set: $priorUserName"
testInvocation='sfdx force:apex:test:run -n "RollupTests" -r human -w 20'
echo "Test command to use: $testInvocation"


# Create Scratch Org
sfdx force:org:create -f config/project-scratch-def.json -a apex-rollup-scratch-org -s -d 1
# Deploy
sfdx force:source:push
# Run tests
eval '$testInvocation'
# Delete scratch org
sfdx force:org:delete -p -u apex-rollup-scratch-org

# If the priorUserName is not blank, reset to it
if test -z "$priorUserName";
then
  echo "Prior user name not set, continuing"
else
  echo "Resetting SFDX to previously authorized org"
  sfdx force:config:set defaultusername=$priorUserName
fi

echo "Build + testing finished successfully"