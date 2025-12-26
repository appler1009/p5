#!/bin/zsh
# Format and cleanup all Swift files in the project using `swift format` (Xcode 16+)

set -euo pipefail

echo "Finding all Swift files in the project..."

# Find all .swift files, excluding .build directory
swift_files=($(find . -name "*.swift" -not -path "./.build/*" -type f))

if [[ ${#swift_files[@]} -eq 0 ]]; then
  echo "No Swift files found."
  exit 0
fi

echo "Formatting ${#swift_files[@]} Swift files..."

# Format Swift files
for file in "${swift_files[@]}"; do
  swift format --in-place "$file"
  echo "Formatted: $file"
done

# Remove trailing whitespaces from Swift files
for file in "${swift_files[@]}"; do
  sed -i '' 's/[[:space:]]*$//' "$file"
  echo "Removed trailing whitespaces: $file"
done

# Remove consecutive empty lines, leaving only one empty line
for file in "${swift_files[@]}"; do
  sed -i '' '/^$/N;/^\n$/d' "$file"
  echo "Removed consecutive empty lines: $file"
done

# Find all .sh files, excluding .build directory
sh_files=($(find . -name "*.sh" -not -path "./.build/*" -type f))

if [[ ${#sh_files[@]} -gt 0 ]]; then
  echo "Cleaning up ${#sh_files[@]} shell script files..."

  # Remove trailing whitespaces from .sh files
  for file in "${sh_files[@]}"; do
    sed -i '' 's/[[:space:]]*$//' "$file"
    echo "Removed trailing whitespaces: $file"
  done

  # Remove consecutive empty lines, leaving only one empty line
  for file in "${sh_files[@]}"; do
    sed -i '' '/^$/N;/^\n$/d' "$file"
    echo "Removed consecutive empty lines: $file"
  done
fi

echo "Formatting and cleanup complete."
