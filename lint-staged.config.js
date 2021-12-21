// we use path.resolve to combat cross-platform
// path delimiter incompatibilities ("/" versus "\\", for instance)
const path = require('path');

const extraCodeCoveragePaths = [
  'extra-tests/classes/RollupTestUtils.cls',
  'extra-tests/classes/RollupTests.cls',
  'extra-tests/classes/RollupEvaluatorTests.cls',
  'extra-tests/classes/RollupRelationshipFieldFinderTests.cls',
  'extra-tests/classes/RollupLoggerTests.cls',
  'extra-tests/classes/RollupQueryBuilderTests.cls',
  'extra-tests/classes/RollupRecursionItemTests.cls',
  'extra-tests/classes/RollupParentResetProcessorTests.cls'
].map(fileName => path.resolve(__dirname + '/' + fileName));

let shouldRunSfdxScanner = false;
let shouldRunExtraCodeCoveragePackageCreation = false;

module.exports = {
  '**/lwc/*.js': filenames => `eslint ${filenames.join(' ')} --fix`,
  '*.{cls,cmp,component,css,html,js,json,md,page,trigger,yaml,yml}': filenames => {
    const commands = filenames.map(filename => {
      if (!shouldRunSfdxScanner && (filename.endsWith('.cls') || filename.endsWith('.trigger'))) {
        shouldRunSfdxScanner = true;
      }

      if (extraCodeCoveragePaths.includes(path.resolve(filename))) {
        shouldRunExtraCodeCoveragePackageCreation = true;
      }

      return `prettier --write '${filename}'`;
    });

    if (shouldRunSfdxScanner) {
      commands.push('npm run scan');
    }
    if (shouldRunExtraCodeCoveragePackageCreation) {
      commands.push('npm run create:package:code-coverage');
    }
    return commands;
  }
};
