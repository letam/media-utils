#!/bin/bash

# Show the last N files with creation, modification, and accessed times
# Usage: show_file_times.sh [directory] [number_of_files] [sort_by]
#   sort_by: modified (default), accessed, or created

DIR="${1:-.}"
NUM_FILES="${2:-10}"
SORT_BY="${3:-modified}"

if [ ! -d "$DIR" ]; then
    echo "Error: Directory '$DIR' not found"
    exit 1
fi

# Determine ls sort flag based on sort_by parameter
case "$SORT_BY" in
    accessed|access)
        LS_FLAG="-lut"
        SORT_LABEL="accessed"
        ;;
    created|birth)
        LS_FLAG="-lUt"
        SORT_LABEL="created"
        ;;
    modified|*)
        LS_FLAG="-lt"
        SORT_LABEL="modified"
        ;;
esac

# Helper function to get access time in human readable format
get_access_time() {
    local filepath="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: Get access time and convert with date
        local access_epoch=$(stat -f "%a" "$filepath")
        date -r "$access_epoch" "+%b %d %H:%M:%S %Y"
    else
        # Linux
        stat -c "%x" "$filepath"
    fi
}

echo "Last $NUM_FILES files sorted by $SORT_LABEL time in: $DIR"
echo ""
echo "File | Created | Modified | Accessed"
echo "---|---|---|---"

# Use ls to sort and get filenames, then get all times
ls $LS_FLAG "$DIR" | head -$((NUM_FILES + 1)) | tail -$NUM_FILES | while read line; do
    # Extract filename (last field after ls output)
    filepath=$(echo "$line" | awk '{print $NF}')

    # If the path doesn't exist as-is, try with directory prepended
    if [ ! -e "$filepath" ]; then
        filepath="$DIR/$filepath"
    fi

    # Skip if file still doesn't exist
    [ -e "$filepath" ] || continue

    # Get creation time (birth time), modification time, and access time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        created=$(stat -f "%SB" "$filepath")
        modified=$(stat -f "%Sm" "$filepath")
        accessed=$(get_access_time "$filepath")
    else
        # Linux
        created=$(stat -c "%w" "$filepath")
        modified=$(stat -c "%y" "$filepath")
        accessed=$(stat -c "%x" "$filepath")
    fi

    # Format output as markdown table row
    filename=$(basename "$filepath")
    echo "$filename | $created | $modified | $accessed"
done
