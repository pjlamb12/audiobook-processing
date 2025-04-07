#!/bin/bash

# --- Script to sanitize filenames in the current directory ---
# Keeps letters (a-z, A-Z) and digits (0-9).
# Replaces spaces ' ' with hyphens '-'.
# Collapses multiple consecutive spaces/hyphens into a single hyphen.
# Removes all other characters.
# Trims leading/trailing hyphens from the name part.
# Preserves original file extensions.

# --- Dry Run Check ---
dry_run=false
if [[ "$1" == "--dry-run" || "$1" == "-n" ]]; then
    dry_run=true
    echo "*** DRY RUN MODE enabled - No files will be renamed. ***"
fi

echo "Sanitizing filenames in the current directory..."
rename_count=0
skip_empty_count=0
skip_exists_count=0
skip_nochange_count=0

# Process files in current directory using find for safety
find . -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' filepath; do
    filename=$(basename "$filepath")
    dir=$(dirname "$filepath") # Usually "." when using -maxdepth 1

    # Skip hidden files (like .DS_Store)
    if [[ "$filename" == .* ]]; then
        continue
    fi

    # Separate stem (name part) and extension (part after last dot)
    if [[ "$filename" == *"."* ]]; then
        extension=".${filename##*.}" # Include the dot
        stem="${filename%.*}"
    else
        extension="" # No extension
        stem="$filename"
    fi

    # --- Process the stem ---
    # 1. Replace spaces with hyphens
    temp_stem1=$(echo "$stem" | tr ' ' '-')
    # 2. Remove all characters that are NOT alphanumeric or hyphen
    temp_stem2=$(echo "$temp_stem1" | tr -cd '[:alnum:]-')
    # 3. Squeeze (collapse) multiple consecutive hyphens into a single hyphen
    temp_stem3=$(echo "$temp_stem2" | tr -s '-')
    # 4. Trim leading and trailing hyphens (if any) using sed
    processed_stem=$(echo "$temp_stem3" | sed -e 's/^-//' -e 's/-$//')
    # --- End Processing ---


    # --- Sanity Checks ---
    # Skip if processing resulted in an empty stem
    # (This check should happen AFTER trimming)
    if [[ -z "$processed_stem" ]]; then
        echo "Skipping '$filename': Sanitized name part is empty after processing."
        skip_empty_count=$((skip_empty_count + 1))
        continue
    fi

    # Reconstruct the new filename
    new_filename="${processed_stem}${extension}"
    # Reconstruct the full path for the potential new file
    new_filepath="${dir}/${new_filename}"

    # Skip if filename hasn't actually changed
    if [[ "$filename" == "$new_filename" ]]; then
        skip_nochange_count=$((skip_nochange_count + 1))
        continue
    fi

    # Safety Check: Does a file with the new name already exist?
    if [[ -e "$new_filepath" ]] && [[ "$filepath" != "$new_filepath" ]]; then
        echo "Skipping rename for '$filename': Target '$new_filename' already exists."
        skip_exists_count=$((skip_exists_count + 1))
        continue
    fi
    # --- End Sanity Checks ---

    # --- Perform rename or dry run ---
    if $dry_run; then
        echo "DRY RUN: Would rename '$filename' -> '$new_filename'"
        rename_count=$((rename_count + 1))
    else
        echo "Renaming '$filename' -> '$new_filename'"
        mv -- "$filepath" "$new_filepath"
        if [[ $? -ne 0 ]]; then
            echo "ERROR: Failed to rename '$filename'. Continuing..."
        else
            rename_count=$((rename_count + 1))
        fi
    fi

done

echo "-------------------------------------"
echo "Finished sanitizing filenames."
if $dry_run; then
    echo "Summary (Dry Run):"
    echo "  Files that would be renamed: $rename_count"
else
    echo "Summary:"
    echo "  Files renamed: $rename_count"
fi
echo "  Files skipped (sanitized name empty): $skip_empty_count"
echo "  Files skipped (no change needed): $skip_nochange_count"
echo "  Files skipped (target name existed): $skip_exists_count"
if $dry_run; then echo "*** DRY RUN MODE was enabled ***"; fi

exit 0