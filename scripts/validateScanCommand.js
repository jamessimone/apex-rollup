import fs from 'fs';

const violationOutputFilePaths = ['coverage/pmd-violations.json', 'coverage/lint-violations.json'];

violationOutputFilePaths.forEach(path => {
  if (fs.existsSync(path)) {
    const fileContents = Buffer.from(fs.readFileSync(path));
    const parsedFileContents = JSON.parse(fileContents.toString());
    if (parsedFileContents.violationCounts.total > 0) {
      throw Error(JSON.stringify(parsedFileContents, null, 2));
    }
  }
});

console.log('No scan violations found');
