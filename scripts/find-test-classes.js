// useful if you're running Rollup tests on a sandbox that also contains other tests
// to be invoked through the package.json script, "testApex" (or the full invocation, via "test")
// e.g. "npm run test" / "npm run testApex" / "yarn test" / "yarn testApex"
var fs = require('fs');

const classList = [];
const verbotenDirectories = ['.node_modules/', 'vscode', '.config/', '.media/', '.yarn.lock/'];

const findClasses = paths => {
  paths.forEach(path => {
    if (verbotenDirectories.indexOf(path) > -1) {
      return;
    }
    if (path.endsWith('.cls/')) {
      classList.push(path.substring(0, path.length - 1));
    }
    fs.readdirSync(path).forEach(innerPath => {
      try {
        // attempt to coerce to a path by adding backslashes and catch anything that isn't
        // it ain't pretty - but it works!
        findClasses([path + '/' + innerPath + '/']);
      } catch (ex) {}
    });
  });
  return classList;
};

// recurses through each directory, finding any test classes along the way
const existingClasses = findClasses(['./rollup', './extra-tests'])
  .map(classPath => classPath.match(/([^\/]+)(Test|Tests)\.cls$/))
  .map(matchResult => (matchResult ? matchResult[0].replace('.cls', '') : ''))
  .filter(string => !!string);

// by logging here, we allow the output to be captured by any caller
console.log(existingClasses.join(','));
