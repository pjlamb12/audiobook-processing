#!/bin/bash

# --- Script to update metadata tags in an existing M4B file ---
# --- Uses atomicparsley (brew install atomicparsley)        ---

# --- Function Definitions ---
usage() {
  echo "Usage: $0 -f <input.m4b> [OPTIONS]"
  echo "  Updates metadata for the specified M4B file. Only provided options are updated."
  echo ""
  echo "  -f <input.m4b>    : Path to the M4B file to update (required)."
  echo "  -t <title>        : Set new Title."
  echo "  -a <author>       : Set new Author (Artist tag)."
  echo "  -A <album>        : Set new Album (often same as Title for audiobooks)."
  echo "  -S <series_name>  : Set new Series Name (TV Show Name tag)."
  echo "  -E <sequence_num> : Set new Sequence number in series (TV Episode Number tag)."
  echo "  -c <cover_art>    : Set new Cover Art from image file (jpg/png)."
  echo "  -g <genre>        : Set new Genre (e.g., Audiobook, Fiction)."
  echo "  -d <description>  : Set new Description/Synopsis."
  echo "  -Y <year>         : Set new Release Year."
  echo "  -N                : Dry run. Show the command without executing it."
  echo "  -h                : Show this help message."
  exit 1
}

# --- Initialize Variables ---
input_file=""
arg_title=""
arg_author=""
arg_album=""
arg_series=""
arg_sequence=""
arg_cover=""
arg_genre=""
arg_description=""
arg_year=""
dry_run=false

# --- Argument Parsing ---
# Note the flags match the usage message
while getopts "hf:t:a:A:S:E:c:g:d:Y:N" opt; do
  case $opt in
    h) usage ;;
    f) input_file="$OPTARG" ;;
    t) arg_title="$OPTARG" ;;
    a) arg_author="$OPTARG" ;;
    A) arg_album="$OPTARG" ;;
    S) arg_series="$OPTARG" ;;
    E) arg_sequence="$OPTARG" ;;
    c) arg_cover="$OPTARG" ;;
    g) arg_genre="$OPTARG" ;;
    d) arg_description="$OPTARG" ;;
    Y) arg_year="$OPTARG" ;;
    N) dry_run=true ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# --- Validate Inputs ---
# Check required input file
if [[ -z "$input_file" ]]; then
  echo "Error: Input file (-f) is required." >&2
  usage
fi

# Expand tilde for input file path
expanded_input_file="$input_file"
if [[ "${input_file:0:1}" == "~" ]]; then
    expanded_input_file="$HOME${input_file:1}"
fi

# Check if input file exists
if [[ ! -f "$expanded_input_file" ]]; then
  echo "Error: Input file '$expanded_input_file' not found." >&2
  exit 1
fi

# Check for atomicparsley dependency
if ! command -v atomicparsley &> /dev/null; then
    echo "Error: 'atomicparsley' command not found." >&2
    echo "Please install it, e.g., using Homebrew: brew install atomicparsley" >&2
    exit 1
fi

# Optional: Validate sequence number is an integer if provided
if [[ -n "$arg_sequence" ]] && ! [[ "$arg_sequence" =~ ^[0-9]+$ ]]; then
    echo "Error: Sequence number (-E) must be an integer." >&2
    exit 1
fi

# --- Build atomicparsley command ---
echo "Preparing to update metadata for: $expanded_input_file"
cmd_args=(atomicparsley "$expanded_input_file")
update_needed=false # Flag to track if any update options were actually given

# Conditionally add arguments based on provided flags
if [[ -n "$arg_title" ]]; then cmd_args+=(--title "$arg_title"); update_needed=true; echo " - Setting Title"; fi
if [[ -n "$arg_author" ]]; then cmd_args+=(--artist "$arg_author"); update_needed=true; echo " - Setting Author/Artist"; fi
if [[ -n "$arg_album" ]]; then cmd_args+=(--album "$arg_album"); update_needed=true; echo " - Setting Album"; fi
if [[ -n "$arg_series" ]]; then cmd_args+=(--TVShowName "$arg_series"); update_needed=true; echo " - Setting Series Name"; fi
if [[ -n "$arg_sequence" ]]; then cmd_args+=(--TVEpisodeNum "$arg_sequence"); update_needed=true; echo " - Setting Series Sequence"; fi
# You could potentially add --tracknum here too if desired:
# if [[ -n "$arg_sequence" ]]; then cmd_args+=(--tracknum "$arg_sequence"); fi
if [[ -n "$arg_cover" ]]; then
    # Expand tilde for cover art path
    expanded_cover_path="$arg_cover"
    if [[ "${arg_cover:0:1}" == "~" ]]; then
        expanded_cover_path="$HOME${arg_cover:1}"
    fi
    # Check if cover art file exists before adding
    if [[ ! -f "$expanded_cover_path" ]]; then
        echo "Warning: Cover art file '$expanded_cover_path' not found. Skipping cover update." >&2
    else
        cmd_args+=(--artwork "$expanded_cover_path"); update_needed=true; echo " - Setting Cover Art from '$expanded_cover_path'";
    fi
fi
if [[ -n "$arg_genre" ]]; then cmd_args+=(--genre "$arg_genre"); update_needed=true; echo " - Setting Genre"; fi
if [[ -n "$arg_description" ]]; then cmd_args+=(--description "$arg_description"); update_needed=true; echo " - Setting Description"; fi
if [[ -n "$arg_year" ]]; then cmd_args+=(--year "$arg_year"); update_needed=true; echo " - Setting Year"; fi

# Exit if no update flags were actually provided
if ! $update_needed; then
    echo "No metadata update options provided. Nothing to do."
    exit 0
fi

# Add --overWrite ONLY if not in dry run mode
if ! $dry_run; then
    cmd_args+=(--overWrite)
fi

# --- Execute or Simulate ---
echo "-------------------------------------"
if $dry_run; then
    echo "DRY RUN: Would execute the following command:"
    # Print the command array with proper quoting for shell
    printf " %q" "${cmd_args[@]}"
    echo # Newline
    echo ""
    echo "File '$expanded_input_file' would NOT be modified."
else
    echo "Executing:"
    printf " %q" "${cmd_args[@]}" # Show command being run
    echo # Newline
    echo ""
    echo "Updating metadata (operates in-place)..."
    # Execute the command
    if "${cmd_args[@]}"; then
        echo "Metadata update successful for '$expanded_input_file'."
    else
        exit_code=$?
        echo "Error: atomicparsley failed with exit code $exit_code." >&2
        exit $exit_code
    fi
fi
echo "-------------------------------------"

exit 0