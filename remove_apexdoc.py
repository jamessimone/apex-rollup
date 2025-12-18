#!/usr/bin/env python3
import re
import sys

def is_apexdoc_block(block_text):
    """Check if this block contains ApexDoc tags"""
    apexdoc_tags = ['@description', '@param', '@return', '@see', '@group', '@example']
    return any(tag in block_text for tag in apexdoc_tags)

def remove_apexdoc_comments(file_path):
    """Remove ApexDoc comment blocks from a file"""
    with open(file_path, 'r') as f:
        content = f.read()

    # Pattern to match /** ... */ blocks (multi-line)
    pattern = r'/\*\*\s*\n(\s*\*[^\n]*\n)*?\s*\*/'

    # Find all matches
    matches = list(re.finditer(pattern, content))

    # Process in reverse to maintain correct indices
    removed_count = 0
    for match in reversed(matches):
        if is_apexdoc_block(match.group(0)):
            content = content[:match.start()] + content[match.end():]
            removed_count += 1

    # Write back
    with open(file_path, 'w') as f:
        f.write(content)

    print(f"Successfully removed {removed_count} ApexDoc comment blocks from {file_path}")
    return removed_count

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 remove_apexdoc.py <file_path>")
        sys.exit(1)

    file_path = sys.argv[1]
    remove_apexdoc_comments(file_path)
