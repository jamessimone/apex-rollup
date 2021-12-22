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

const nebulaLoggerAdapterPath = path.resolve(__dirname + '/plugins/NebulaLogger/classes/RollupNebulaLoggerAdapter.cls');

let shouldRunSfdxScanner = false;
let shouldRunExtraCodeCoveragePackageCreation = false;
let shouldRunNebulaLoggerPackageCreation = false;

module.exports = {
  '**/lwc/*.js': filenames => `eslint ${filenames.join(' ')} --fix`,
  '*.{cls,cmp,component,css,html,js,json,md,page,trigger,yaml,yml}': filenames => {
    const commands = filenames.map(filename => {
      if (!shouldRunSfdxScanner && (filename.endsWith('.cls') || filename.endsWith('.trigger'))) {
        shouldRunSfdxScanner = true;
      }

      const resolvedPath = path.resolve(filename);

      if (extraCodeCoveragePaths.includes(resolvedPath)) {
        shouldRunExtraCodeCoveragePackageCreation = true;
      }
      if (nebulaLoggerAdapterPath === resolvedPath) {
        shouldRunNebulaLoggerPackageCreation = true;
      }
      return `prettier --write '${filename}'`;
    });

    if (shouldRunSfdxScanner) {
      commands.push('npm run scan');
    }
    if (shouldRunExtraCodeCoveragePackageCreation) {
      commands.push('npm run create:package:code-coverage');
    }
    if (shouldRunNebulaLoggerPackageCreation) {
      commands.push('npm run create:package:nebula:adapter');
    }
    return commands;
  }
};
