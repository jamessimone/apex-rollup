#!/usr/bin/bash

set -e
trap 'catch $? $LINENO' EXIT
catch() {
  if [ "$1" != "0" ]; then
    echo "Error $1 occurred on $2"
    # Always delete scratch org
    sfdx force:org:delete -p -u scratch-org
  fi
}

echo "Starting build script"

# Authorize Dev Hub
sfdx force:auth:sfdxurl:store -f ./DEVHUB_SFDX_URL.txt -a apex-mocks -d
# Create Scratch Org
sfdx force:org:create -f config/project-scratch-def.json -a scratch-org -s -d 1
# Deploy
sfdx force:source:push
# Run tests
sfdx force:apex:test:run -c -r human -d ./tests/apex -w 20
# Delete scratch org
sfdx force:org:delete -p -u scratch-org

echo "Build + testing finished successfully"