#!/bin/bash

# --- Script to Copy AIFF files from a source (e.g., CD Volume), ---
# --- sanitize and rename them with 3-digit padding in a temporary location, ---
# --- then move to final destination folder.                     ---

# --- Configuration ---
# This script is currently hardcoded for AIFF files due to the regex
# To adapt for other types, change RENAME_PATTERN, EXPECTED_EXTENSION,
# and potentially REGEX_CAPTURE_TEXT_PART.
RENAME_PATTERN="*.aiff"
EXPECTED_EXTENSION=".aiff"
# Regex captures number, space, then the main text part *before* the extension
REGEX_CAPTURE_TEXT_PART="^[0-9]+[[:space:]]+(.*)${EXPECTED_EXTENSION//./\\.}$" # Escape dot in extension
# Delimiter to use in the *new* filename between the number and the rest
NEW_DELIMITER="-" # Using hyphen as delimiter now

# --- Function Definitions ---
usage() {
  echo "Usage: $0 -s <source_dir> -d <dest_dir> -n <start_num> [-N]"
  echo "  -s <source_dir>  : Path to the source directory (e.g., /Volumes/CD_NAME) (required)."
  echo "  -d <dest_dir>    : Path to the final destination directory (required, '~' expansion supported)."
  echo "  -n <start_num>   : Starting number for renaming sequence (required)."
  echo "  -N               : Dry run. Simulate copy, rename, and move without making changes."
  echo "  -h               : Show this help message."
  exit 1
}

# Initialize vars used in cleanup
temp_dir=""

cleanup() {
  if [[ -n "$temp_dir" ]] && [[ -d "$temp_dir" ]]; then
    echo "Cleaning up temporary directory: $temp_dir"
    rm -rf "$temp_dir"
  fi
}

# --- Argument Parsing ---
source_dir=""
dest_dir=""
start_num=""
dry_run=false

while getopts "hs:d:n:N" opt; do
  # ... (argument parsing remains the same) ...
  case $opt in
    h) usage ;;
    s) source_dir="$OPTARG" ;;
    d) dest_dir="$OPTARG" ;;
    n) start_num="$OPTARG" ;;
    N) dry_run=true ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# --- Validate Inputs ---
# ... (validations remain the same) ...
if [[ -z "$source_dir" ]] || [[ -z "$dest_dir" ]] || [[ -z "$start_num" ]]; then echo "Error: Source directory (-s), destination directory (-d), and starting number (-n) are required."; usage; fi
if [[ ! -d "$source_dir" ]]; then echo "Error: Source directory '$source_dir' not found."; exit 1; fi
if ! [[ "$start_num" =~ ^[0-9]+$ ]]; then echo "Error: Starting number (-n) must be an integer."; exit 1; fi
# ...

# --- Expand Tilde (~) in Destination Path ---
expanded_dest_dir="$dest_dir"
if [[ "${dest_dir:0:1}" == "~" ]]; then expanded_dest_dir="$HOME${dest_dir:1}"; echo "Info: Expanded destination path '~' to '$HOME'."; fi

# --- Prepare Final Destination and Temporary Directory ---
# ... (directory preparation remains the same) ...
if $dry_run; then
    echo "DRY RUN: Would ensure final destination directory exists: '$expanded_dest_dir'"
    dest_base_dir=$(dirname "$expanded_dest_dir")
     if [[ ! -d "$dest_base_dir" ]]; then echo "DRY RUN WARNING: Base directory '$dest_base_dir' for final destination does not exist."; fi
else
    echo "Ensuring final destination directory exists: '$expanded_dest_dir'"
    mkdir -p "$expanded_dest_dir" || { echo "Error: Could not create final destination directory '$expanded_dest_dir'."; exit 1; }
fi
temp_dir=$(mktemp -d "${expanded_dest_dir}/temp_copy_rename_XXXXXX")
if [[ $? -ne 0 ]] || [[ -z "$temp_dir" ]]; then echo "Error: Failed to create temporary directory in '$expanded_dest_dir'."; exit 1; fi
echo "Created temporary directory: $temp_dir"
trap cleanup EXIT SIGINT SIGTERM
echo "-------------------------------------"

# --- Step 1: Copy Files (Source -> Temp) ---
# ... (copy step remains the same) ...
echo "Step 1: Copying files from '$source_dir' to temporary directory '$temp_dir'..."
rsync_cmd_copy=(rsync -avh --progress)
if $dry_run; then rsync_cmd_copy+=(-n); echo "DRY RUN: Simulating file copy to temp directory..."; fi
rsync_cmd_copy+=("$source_dir/" "$temp_dir/")
"${rsync_cmd_copy[@]}"
rsync_exit_code=$?
if [[ $rsync_exit_code -ne 0 ]]; then echo "Error: rsync copy process failed with exit code $rsync_exit_code."; if $dry_run; then echo "(Dry run mode - error check is indicative)"; fi; exit $rsync_exit_code; fi
if $dry_run; then echo "DRY RUN: File copy simulation to temp complete."; else echo "File copy to temp complete."; fi
echo "-------------------------------------"

# --- Step 2: Sanitize and Rename Files (Inside Temp) ---
echo "Step 2: Sanitizing and Renaming '$RENAME_PATTERN' files inside temporary directory '$temp_dir'..."
counter=$start_num
rename_ops=0
skip_pattern=0
skip_empty_count=0 # Added counter
skip_exists=0
skip_nochange_count=0 # Added counter

# Target the find command at the *temporary* directory
find "$temp_dir" -maxdepth 1 -name "$RENAME_PATTERN" -print0 | sort -zV | while IFS= read -r -d $'\0' old_filepath; do
    old_filename=$(basename "$old_filepath")

    # Try to match the expected pattern (Number Text.Extension)
    if [[ "$old_filename" =~ $REGEX_CAPTURE_TEXT_PART ]]; then
        original_text_part="${BASH_REMATCH[1]}" # The captured text part

        # --- Apply Sanitization Logic ---
        # 1. Replace spaces with hyphens
        temp_stem1=$(echo "$original_text_part" | tr ' ' '-')
        # 2. Remove all characters that are NOT alphanumeric or hyphen
        temp_stem2=$(echo "$temp_stem1" | tr -cd '[:alnum:]-')
        # 3. Squeeze (collapse) multiple consecutive hyphens into a single hyphen
        temp_stem3=$(echo "$temp_stem2" | tr -s '-')
        # 4. Trim leading and trailing hyphens (if any)
        sanitized_text_part=$(echo "$temp_stem3" | sed -e 's/^-//' -e 's/-$//')
        # --- End Sanitization ---

        # Skip if sanitizing resulted in an empty text part
        if [[ -z "$sanitized_text_part" ]]; then
            echo "Skipping rename for '$old_filename': Sanitized text part is empty."
            skip_empty_count=$((skip_empty_count + 1))
            continue # Don't increment counter
        fi

        # Format the leading number
        new_number_formatted=$(printf "%03d" $counter)

        # Construct the new filename using number, delimiter, sanitized text, and extension
        new_filename="${new_number_formatted}${NEW_DELIMITER}${sanitized_text_part}${EXPECTED_EXTENSION}"
        new_filepath="$(dirname "$old_filepath")/$new_filename"

        # Skip if filename hasn't changed after sanitizing and renumbering
        if [[ "$old_filename" == "$new_filename" ]]; then
            echo "Skipping rename (name already correct/no changes needed): $old_filename"
            skip_nochange_count=$((skip_nochange_count + 1))
            # Even if no change, it holds a place in the sequence if pattern matched
            counter=$((counter + 1))
            continue
        fi

        # Safety Check: Does a file with the new name already exist in temp?
        if [[ -e "$new_filepath" ]] && [[ "$old_filepath" != "$new_filepath" ]]; then
             echo "ERROR: Target temporary file '$new_filename' already exists! Skipping rename for '$old_filename'."
             skip_exists=$((skip_exists + 1))
             # Consume the sequence number because this file *would* have used it
             counter=$((counter + 1))
             continue
        fi

        # --- Perform Rename or Dry Run ---
        if $dry_run; then
            echo "DRY RUN: Would rename (in temp): '$old_filename'  ->  '$new_filename'"
            rename_ops=$((rename_ops + 1))
            counter=$((counter + 1)) # Increment counter for successful simulation
        else
            echo "Renaming (in temp): '$old_filename'  ->  '$new_filename'"
            mv -- "$old_filepath" "$new_filepath"
            if [[ $? -ne 0 ]]; then
                echo "ERROR: Failed to rename '$old_filename' in temp directory. Stopping script."
                exit 1 # Exit if rename fails
            else
                rename_ops=$((rename_ops + 1))
                counter=$((counter + 1)) # Increment counter for successful rename
            fi
        fi
    else
        # Filename did not match the Number Text.Extension pattern
        echo "Skipping rename (pattern not matched): $old_filename"
        skip_pattern=$((skip_pattern + 1))
        # Do not increment counter for pattern mismatch
    fi
done

echo "Sanitize/Rename process within temp directory finished."
echo "Rename Summary:"
if $dry_run; then echo "  Rename operations simulated: $rename_ops"; else echo "  Files renamed in temp: $rename_ops"; fi
echo "  Files skipped (pattern mismatch): $skip_pattern"
echo "  Files skipped (sanitized name empty): $skip_empty_count"
echo "  Files skipped (no change needed): $skip_nochange_count"
echo "  Files skipped (target name existed in temp): $skip_exists"
echo "-------------------------------------"

# --- Step 3: Move Files (Temp -> Final Destination) ---
# ... (move step remains the same) ...
echo "Step 3: Moving files from temporary directory '$temp_dir' to final destination '$expanded_dest_dir'..."
rsync_cmd_move=(rsync -ah --remove-source-files)
if $dry_run; then rsync_cmd_move+=(-n --stats); echo "DRY RUN: Simulating move from temp to final destination..."; fi
rsync_cmd_move+=("$temp_dir/" "$expanded_dest_dir/")
"${rsync_cmd_move[@]}"
rsync_move_exit_code=$?
if [[ $rsync_move_exit_code -ne 0 ]]; then echo "Error: rsync move process failed with exit code $rsync_move_exit_code."; if $dry_run; then echo "(Dry run mode - error check is indicative)"; fi; echo "Warning: Files may still be in temporary directory '$temp_dir' due to move error."; else if $dry_run; then echo "DRY RUN: File move simulation complete."; else echo "File move complete."; fi; fi
echo "-------------------------------------"

# --- Final Cleanup ---
echo "Process finished."
if $dry_run; then echo "*** DRY RUN MODE was enabled - No actual changes were made to final destination or source. Temp dir was created and will be removed. ***"; fi
exit 0 # Cleanup is handled by the trap