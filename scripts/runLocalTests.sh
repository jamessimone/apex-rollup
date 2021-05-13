#  presumes you are running from the base directory
testNames=$(node ./scripts/find-test-classes.js)
sfdx force:apex:test:run -n $testNames -w 10