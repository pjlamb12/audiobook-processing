#!/bin/bash

# --- Script to show key metadata tags from an M4B file ---
# --- v2: Adds debug mode and "not found" message      ---

# --- Function Definitions ---
usage() {
  echo "Usage: $0 [-d] <path_to_m4b_file>"
  echo "  Displays common audiobook metadata tags for the specified M4B file."
  echo ""
  echo "  -d, --debug : Print the full raw metadata block from ffprobe for diagnosis."
  echo "  -h          : Show this help message."
  exit 1
}

# Function to extract and print a specific tag from the metadata block
print_tag() {
    local meta_block="$1"
    local tag_name="$2"
    local display_name="$3"
    local found_value=""
    
    # Grep for the key (case-insensitive), then cut to get the value
    found_value=$(echo "$meta_block" | grep -iE "^TAG:${tag_name}=" | cut -d'=' -f2-)
    
    # Only print if a value was found and update the global found flag
    if [[ -n "$found_value" ]]; then
        printf "%-15s: %s\n" "$display_name" "$found_value"
        # Set the global TAGS_FOUND flag to 1
        TAGS_FOUND=1
    fi
}

# --- Argument Parsing & Validation ---
debug_mode=false
m4b_file=""

# Handle flags and the positional file argument
for arg in "$@"; do
  case $arg in
    -h) usage ;;
    -d|--debug)
      debug_mode=true
      shift # Move to next argument
      ;;
    *)
      # Assume the first non-flag argument is the file
      if [[ -z "$m4b_file" ]]; then
        m4b_file="$arg"
      fi
      ;;
  esac
done

if [[ -z "$m4b_file" ]]; then echo "Error: No M4B file specified." >&2; usage; fi

# Expand tilde (~) in input file path
expanded_m4b_file="$m4b_file"
if [[ "${m4b_file:0:1}" == "~" ]]; then
    expanded_m4b_file="$HOME${m4b_file:1}"
fi

# Check if file exists
if [[ ! -f "$expanded_m4b_file" ]]; then echo "Error: File not found: $expanded_m4b_file" >&2; exit 1; fi
# Check for ffprobe dependency
if ! command -v ffprobe &> /dev/null; then echo "Error: 'ffprobe' command not found." >&2; echo "Install: brew install ffmpeg"; exit 1; fi

# --- Get Metadata ---
echo "Reading Metadata for: $expanded_m4b_file"
echo "--------------------------------------------------"

metadata=$(ffprobe -v quiet -print_format ini -show_format "$expanded_m4b_file")

# If debug mode is on, print the raw metadata and exit
if $debug_mode; then
    echo "--- START FFPROBE DEBUG OUTPUT ---"
    echo "$metadata"
    echo "--- END FFPROBE DEBUG OUTPUT ---"
    exit 0
fi

# Initialize a flag to track if we find anything
TAGS_FOUND=0

# --- Print Desired Tags using the function ---
print_tag "$metadata" "title"         "Title"
print_tag "$metadata" "artist"        "Author/Artist"
print_tag "$metadata" "album"         "Album"
print_tag "$metadata" "show"          "Series"
print_tag "$metadata" "episode_id"    "Sequence #"
print_tag "$metadata" "track"         "Track #"
print_tag "$metadata" "genre"         "Genre"
print_tag "$metadata" "date"          "Year"
# For description, check multiple possible keys
print_tag "$metadata" "comment"       "Comment"
print_tag "$metadata" "synopsis"      "Synopsis"
print_tag "$metadata" "description"   "Description"

# --- Final Check ---
if [[ $TAGS_FOUND -eq 0 ]]; then
    echo "No common metadata tags found in this file."
    echo "Tip: Rerun with the -d or --debug flag to see all raw metadata."
fi

echo "--------------------------------------------------"

exit 0