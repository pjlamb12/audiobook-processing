#!/bin/bash

# --- Configuration ---
# Get starting number from the first command-line argument. Default to 1 if not provided.
start_number="${1:-1}"
if ! [[ "$start_number" =~ ^[0-9]+$ ]]; then
    echo "Error: Starting number must be an integer."
    exit 1
fi
counter=$start_number

# Directory to process (set to "." for the current directory)
target_dir="."
file_pattern="*.mp3" # Files to rename

# Regex to capture the part of the filename *after* the initial number and the first space.
# It assumes filenames start like "1 ..." or "10 ..." or "100 ...". Adjust if pattern is different.
# ^[0-9]+ : Matches one or more digits at the start of the string.
# [ ]     : Matches the literal space immediately following the digits.
# (.*)    : Captures everything after that first space into group 1.
regex_capture_rest='^[0-9]+ (.*)$'

# Delimiter to use in the *new* filename between the number and the rest
new_delimiter=" "

# --- Safety Check / Dry Run Option ---
# Check if the second argument is --dry-run or -n
dry_run=false
if [[ "$2" == "--dry-run" || "$2" == "-n" ]]; then
    dry_run=true
    echo "*** DRY RUN MODE enabled - No files will be renamed. ***"
    echo "---------------------------------------------------------"
fi

echo "Starting rename process in directory: $target_dir"
echo "File pattern: $file_pattern"
echo "Starting number sequence with: $start_number (padded to 3 digits)"
echo "---------------------------------------------------------"

# --- Main Processing Loop ---
# Use 'find' for safety with filenames, pipe to 'sort -V' for natural numeric sort, then loop.
# 'find' gets files based on pattern.
# 'sort -V' sorts naturally (1, 2, ..., 99, 100, 101). '-V' is the key here.
# 'while read' processes each line. Null delimiters handle special filenames.
find "$target_dir" -maxdepth 1 -name "$file_pattern" -print0 | sort -zV | while IFS= read -r -d $'\0' old_filepath; do
    # Get just the filename from the full path
    old_filename=$(basename "$old_filepath")

    # Extract the part of the filename *after* the initial number and first space
    if [[ "$old_filename" =~ $regex_capture_rest ]]; then
        rest_of_name="${BASH_REMATCH[1]}" # Get the captured part (everything after number and space)

        # --- MODIFIED LINE HERE ---
        # Format the new number: %03d pads with leading zeros if the number is less than 3 digits.
        new_number_formatted=$(printf "%03d" $counter)
        # --- END MODIFIED LINE ---

        # Construct the new filename
        new_filename="${new_number_formatted}${new_delimiter}${rest_of_name}"
        new_filepath="$target_dir/$new_filename" # Construct the potential new full path

        # Safety: Avoid renaming if the name would be unchanged
        if [[ "$old_filename" == "$new_filename" ]]; then
            echo "Skipping (name already correct): $old_filename"
            counter=$((counter + 1)) # Still increment the counter
            continue
        fi

        # --- Perform Rename or Show Dry Run ---
        if $dry_run; then
            # Only print what would happen
            echo "DRY RUN: Would rename '$old_filename'  ->  '$new_filename'"
        else
            # Actual renaming logic
            # Safety: Check if a file with the new name already exists
            if [[ -e "$new_filepath" ]]; then
                 echo "ERROR: Target file '$new_filename' already exists! Skipping rename for '$old_filename'."
                 # Optionally increment counter even on skip? Depends on desired behavior.
                 # Let's increment so the sequence continues for the next file.
                 counter=$((counter + 1))
                 continue # Skip to the next file
            else
                echo "Renaming '$old_filename'  ->  '$new_filename'"
                # Use 'mv --' to prevent issues if a filename starts with a dash
                mv -- "$old_filepath" "$new_filepath"
                # Check if mv command succeeded
                if [[ $? -ne 0 ]]; then
                    echo "ERROR: Failed to rename '$old_filename'. Stopping script."
                    exit 1 # Stop the script on failure
                fi
            fi
        fi

        # Increment the counter for the next file
        counter=$((counter + 1))
    else
        # If the filename didn't match the expected pattern (e.g., doesn't start with number+space)
        echo "Skipping (pattern not matched): $old_filename"
        # Do not increment counter if file is skipped due to pattern mismatch
    fi
done

echo "---------------------------------------------------------"
echo "Rename process finished."
if $dry_run; then
    echo "*** DRY RUN MODE was enabled - No files were actually renamed. ***"
fi

exit 0