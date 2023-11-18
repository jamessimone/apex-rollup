# presumes you are running from the base directory
testNames=$(node ./scripts/find-test-classes.js)
sf apex run test --class-names $testNames --wait 30