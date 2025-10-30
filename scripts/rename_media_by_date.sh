#!/bin/bash

# Usage:
#   ./rename_by_date.sh IMG
#   ./rename_by_date.sh holiday
#   ./rename_by_date.sh "IMG|VID"   # multiple patterns using regex OR

# --- Read pattern argument ---
pattern="$1"

if [ -z "$pattern" ]; then
  echo "Usage: $0 <pattern>"
  echo "Example: $0 IMG"
  exit 1
fi

# Enable case-insensitive globbing for extensions
shopt -s nocaseglob

# Gather all matching files first
files=( *.{jpg,jpeg,png,mp4,mov} )

# Filter files matching the provided pattern
filtered=()
for f in "${files[@]}"; do
  [[ -f "$f" && "$f" =~ $pattern ]] && filtered+=("$f")
done

if [ ${#filtered[@]} -eq 0 ]; then
  echo "No files found matching pattern: $pattern"
  exit 0
fi

# Process matching files
for file in "${filtered[@]}"; do
  # --- macOS version ---
  created=$(stat -f "%SB" -t "%Y-%m-%d %H%M" "$file")

  # --- Linux version ---
  # created=$(date -d @"$(stat -c %W "$file")" "+%Y-%m-%d %H%M")
  # if [ "$created" = "@0" ] || [ -z "$created" ]; then
  #   created=$(date -d @"$(stat -c %Y "$file")" "+%Y-%m-%d %H%M")
  # fi

  # Only rename if not already prefixed
  if [[ ! "$file" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{4}\  ]]; then
    newname="${created} ${file}"
    mv -n "$file" "$newname"
    echo "Renamed: $file -> $newname"
  else
    echo "Skipped (already prefixed): $file"
  fi
done

