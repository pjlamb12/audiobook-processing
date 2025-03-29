#!/bin/bash

# --- Script to add .aiff extension to files in the current directory ---
# --- if they don't appear to already have it (case-insensitive).   ---

# --- Configuration ---
EXTENSION_TO_ADD=".aiff"
# Case-insensitive regex to check if extension already exists
# Looks for a dot followed by a, i, f, f at the very end ($)
EXISTING_EXT_REGEX='\.([aA][iI][fF][fF])$'

# --- Dry Run Check ---
dry_run=false
if [[ "$1" == "--dry-run" || "$1" == "-n" ]]; then
    dry_run=true
    echo "*** DRY RUN MODE enabled - No files will be renamed. ***"
fi

echo "Checking files in the current directory for missing '$EXTENSION_TO_ADD' extension..."
rename_count=0
skip_exists_count=0
skip_has_ext_count=0

# Use find for robust file handling, including spaces/special chars
# -maxdepth 1: Only current directory
# -type f: Only files (not directories)
# -print0 / read -d $'\0': Handle special characters safely
find . -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' filepath; do
    # Get just the filename from the path (e.g., "./myfile" -> "myfile")
    filename=$(basename "$filepath")

    # Skip hidden files (optional but often desired)
    if [[ "$filename" == .* ]]; then
        continue
    fi

    # Check if filename already ends with the extension (case-insensitive)
    if [[ "$filename" =~ $EXISTING_EXT_REGEX ]]; then
        # echo "Skipping (already has $EXTENSION_TO_ADD): $filename" # Can be noisy
        skip_has_ext_count=$((skip_has_ext_count + 1))
        continue
    fi

    # --- File needs the extension added ---

    # Construct new name and path
    # Note: filepath might be like "./filename", so new path is "./filename.aiff"
    new_filepath="${filepath}${EXTENSION_TO_ADD}"
    new_filename="${filename}${EXTENSION_TO_ADD}" # For messages

    # Safety Check: Does a file with the new name already exist?
    if [[ -e "$new_filepath" ]]; then
        echo "Skipping rename for '$filename': Target '$new_filename' already exists."
        skip_exists_count=$((skip_exists_count + 1))
        continue
    fi

    # --- Perform rename or dry run ---
    if $dry_run; then
        echo "DRY RUN: Would rename '$filename' -> '$new_filename'"
        rename_count=$((rename_count + 1))
    else
        echo "Renaming '$filename' -> '$new_filename'"
        # Use 'mv --' to handle filenames that might start with a dash
        mv -- "$filepath" "$new_filepath"
        if [[ $? -ne 0 ]]; then
            echo "ERROR: Failed to rename '$filename'. Continuing..."
            # Consider adding an error count or stopping if preferred
        else
            rename_count=$((rename_count + 1))
        fi
    fi
done

echo "-------------------------------------"
echo "Finished checking files."
if $dry_run; then
    echo "Summary (Dry Run):"
    echo "  Files that would get '$EXTENSION_TO_ADD' added: $rename_count"
else
    echo "Summary:"
    echo "  Files renamed: $rename_count"
fi
echo "  Files skipped (already had $EXTENSION_TO_ADD): $skip_has_ext_count"
echo "  Files skipped (target name existed): $skip_exists_count"
if $dry_run; then echo "*** DRY RUN MODE was enabled ***"; fi

exit 0