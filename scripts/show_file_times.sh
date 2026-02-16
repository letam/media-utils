#!/bin/bash

# Show the last N most recently modified files with creation and modification times
# Usage: show_file_times.sh [directory] [number_of_files]

DIR="${1:-.}"
NUM_FILES="${2:-10}"

if [ ! -d "$DIR" ]; then
    echo "Error: Directory '$DIR' not found"
    exit 1
fi

echo "Last $NUM_FILES most recently modified files in: $DIR"
echo ""
echo "File | Created | Modified"
echo "---|---|---"

ls -lt "$DIR" | head -$((NUM_FILES + 1)) | tail -$NUM_FILES | awk '{print $NF}' | while read f; do
    filepath="$DIR/$f"

    # Skip if file doesn't exist (can happen with special characters)
    [ -e "$filepath" ] || continue

    # Get creation time (birth time) and modification time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        created=$(stat -f "%SB" "$filepath")
        modified=$(stat -f "%Sm" "$filepath")
    else
        # Linux
        created=$(stat -c "%w" "$filepath")
        modified=$(stat -c "%y" "$filepath")
    fi

    # Format output as markdown table row
    filename=$(basename "$filepath")
    echo "$filename | $created | $modified"
done
