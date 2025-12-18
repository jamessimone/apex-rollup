const fs = require('fs');
const path = require('path');

function isApexDocBlock(blockText) {
    const apexdocTags = ['@description', '@param', '@return', '@see', '@group', '@example'];
    return apexdocTags.some(tag => blockText.includes(tag));
}

function removeApexDocComments(filePath) {
    const content = fs.readFileSync(filePath, 'utf8');

    // Pattern to match /** ... */ blocks (multi-line)
    const pattern = /\/\*\*\s*\n(\s*\*[^\n]*\n)*?\s*\*\//g;

    let result = content;
    const matches = [];
    let match;

    // Collect all matches with their positions
    while ((match = pattern.exec(content)) !== null) {
        matches.push({
            text: match[0],
            start: match.index,
            end: match.index + match[0].length
        });
    }

    // Process in reverse to maintain correct indices
    let removedCount = 0;
    for (let i = matches.length - 1; i >= 0; i--) {
        if (isApexDocBlock(matches[i].text)) {
            result = result.substring(0, matches[i].start) + result.substring(matches[i].end);
            removedCount++;
        }
    }

    fs.writeFileSync(filePath, result, 'utf8');
    console.log(`Successfully removed ${removedCount} ApexDoc comment blocks from ${filePath}`);
}

const filePath = process.argv[2];
if (!filePath) {
    console.error('Usage: node remove-apexdoc.js <file_path>');
    process.exit(1);
}

removeApexDocComments(filePath);
