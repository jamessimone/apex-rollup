import fs from 'fs';

const violationOutputFilePaths = ['coverage/pmd-violations.json', 'coverage/lint-violations.json'];

violationOutputFilePaths.forEach(path => {
  if (fs.existsSync(path)) {
    let violations = {
      violationCounts: { total: 0 }
    };
    try {
      const fileContents = Buffer.from(fs.readFileSync(path));
      violations = JSON.parse(fileContents.toString());
    } catch (ex) {
      console.warn('Error reading file contents:', ex);
    }
    if (parsedFileContents.violationCounts.total > 0) {
      throw Error(JSON.stringify(parsedFileContents, null, 2));
    }
  }
});

console.log('No scan violations found');
