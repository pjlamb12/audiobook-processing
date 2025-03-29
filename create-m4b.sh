#!/bin/bash

# --- Script Configuration ---
DEFAULT_BITRATE="128k" # Default AAC bitrate (e.g., 96k, 128k, 192k)

# --- Function Definitions ---
usage() {
  echo "Usage: $0 -i <input_dir> -o <output_m4b> [-t <title>] [-a <author>] [-c <cover_art.jpg>] [-b <bitrate>] [-n]"
  echo "  -i <input_dir>    : Directory containing sorted AIFF files (required)."
  echo "  -o <output_m4b>   : Path for the output M4B file (required, '~' expansion supported)."
  echo "  -t <title>        : Audiobook title metadata (optional)."
  echo "  -a <author>       : Audiobook author/artist metadata (optional)."
  echo "  -c <cover_art>    : Path to cover art image (jpg/png, optional)."
  echo "  -b <bitrate>      : AAC audio bitrate (e.g., 96k, 128k, default: ${DEFAULT_BITRATE}, optional)."
  echo "  -n                : Dry run. Perform all steps except final encoding, show command."
  echo "  -h                : Show this help message."
  exit 1
}

# Function to clean up temporary files
cleanup() {
  # Check if variables are set and files exist before trying to remove
  if [[ -n "$concat_list_file" ]] && [[ -f "$concat_list_file" ]]; then
    echo "Cleaning up temporary concat list: $concat_list_file"
    rm "$concat_list_file"
  fi
  if [[ -n "$metadata_file" ]] && [[ -f "$metadata_file" ]]; then
    echo "Cleaning up temporary metadata file: $metadata_file"
    rm "$metadata_file"
  fi
}

# --- Argument Parsing ---
input_dir=""
output_m4b=""
arg_title=""
arg_author=""
arg_cover=""
arg_bitrate="${DEFAULT_BITRATE}"
dry_run=false # Default to not dry run

# Initialize temp file vars to avoid errors in cleanup if they aren't created
concat_list_file=""
metadata_file=""

while getopts "hni:o:t:a:c:b:" opt; do
  case $opt in
    h) usage ;;
    n) dry_run=true ;;
    i) input_dir="$OPTARG" ;;
    o) output_m4b="$OPTARG" ;;
    t) arg_title="$OPTARG" ;;
    a) arg_author="$OPTARG" ;;
    c) arg_cover="$OPTARG" ;;
    b) arg_bitrate="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# --- Validate Required Inputs ---
if [[ -z "$input_dir" ]] || [[ -z "$output_m4b" ]]; then
  echo "Error: Input directory (-i) and output file (-o) are required."
  usage
fi

# --- Validate Paths and Dependencies ---
if [[ ! -d "$input_dir" ]]; then
  echo "Error: Input directory '$input_dir' not found."
  exit 1
fi
if [[ -n "$arg_cover" ]] && [[ ! -f "$arg_cover" ]]; then
  echo "Error: Cover art file '$arg_cover' not found."
  exit 1
fi
if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null; then
    echo "Error: 'ffmpeg' or 'ffprobe' command not found."
    echo "Please install ffmpeg (e.g., 'brew install ffmpeg')."
    exit 1
fi

# --- Expand Tilde (~) in Output Path ---
expanded_output_path="$output_m4b" # Default to original path
if [[ "${output_m4b:0:1}" == "~" ]]; then
    # If path starts with ~, replace ~ with the $HOME environment variable
    expanded_output_path="$HOME${output_m4b:1}"
    echo "Info: Expanded output path '~' to '$HOME'."
fi

# --- Check if Output Directory Exists ---
# Get the directory part of the potentially expanded path
output_dir=$(dirname "$expanded_output_path")
# Check if the directory exists
if [[ ! -d "$output_dir" ]]; then
    echo "Error: Output directory '$output_dir' does not exist."
    echo "Please create the directory first or specify a different output path."
    exit 1
fi

# --- Prepare for Processing ---
# Set trap to ensure cleanup function is called on exit or interrupt
trap cleanup EXIT SIGINT SIGTERM

if $dry_run; then
    echo "*** DRY RUN MODE ENABLED ***"
fi
echo "Starting Audiobook Creation Process..."
echo "Input Directory: $input_dir"
echo "Output File: $expanded_output_path" # Use expanded path
[[ -n "$arg_title" ]] && echo "Title: $arg_title"
[[ -n "$arg_author" ]] && echo "Author: $arg_author"
[[ -n "$arg_cover" ]] && echo "Cover Art: $arg_cover"
echo "Audio Bitrate: $arg_bitrate"
echo "-------------------------------------"

# Create temporary files safely
concat_list_file=$(mktemp /tmp/ffmpeg_concat_list.XXXXXX)
if [[ $? -ne 0 ]]; then echo "Error creating temp concat file"; exit 1; fi
metadata_file=$(mktemp /tmp/ffmpeg_metadata.XXXXXX)
if [[ $? -ne 0 ]]; then echo "Error creating temp metadata file"; exit 1; fi

# --- Generate File List, Chapter Times, and Titles ---
echo "Scanning and sorting AIFF files..."
unset chapter_times chapter_titles # Clear arrays just in case
total_duration_ms=0 # Use milliseconds for precision
file_count=0

# Use Process Substitution with null delimiters for safety and correct sorting
while IFS= read -r -d $'\0' file; do
    file_count=$((file_count + 1))
    filename=$(basename "$file")
    echo "Processing: $filename"

    # Get absolute path for ffmpeg concat list (safest)
    abs_path=$(cd "$(dirname "$file")" && pwd)/$(basename "$file")
    # Add file to ffmpeg concat list, escaping single quotes within the path
    echo "file '${abs_path//\'/\'\\\'\'}'" >> "$concat_list_file"

    # Get duration using ffprobe
    duration_s=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file")
    if [[ -z "$duration_s" ]]; then
        echo "Error: Could not get duration for '$filename'. Aborting."
        exit 1
    fi
    # Convert duration from seconds (float) to milliseconds (integer) using awk
    duration_ms=$(awk -v dur="$duration_s" 'BEGIN{printf "%.0f", dur * 1000}')

    # Store chapter start time (current total duration in ms)
    chapter_times+=($total_duration_ms)

    # Extract chapter title from filename (remove number and extension)
    # This regex assumes "NN Title.aiff" or "NN - Title.aiff" format
    if [[ "$filename" =~ ^[0-9]+[[:space:]]*[-[:space:]]*(.*)\.aiff$ ]]; then
         title="${BASH_REMATCH[1]}"
         # Trim leading/trailing whitespace from extracted title
         title=$(echo "$title" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
         # Fallback title if pattern fails (filename without extension)
         title="${filename%.*}"
    fi
    chapter_titles+=("$title")
    echo "  -> Chapter Title: '$title', Start: ${total_duration_ms}ms, Duration: ${duration_ms}ms"

    # Update total duration
    total_duration_ms=$((total_duration_ms + duration_ms))

done < <(find "$input_dir" -maxdepth 1 -name "*.aiff" -print0 | sort -zV)

# Check if any files were found
if [[ $file_count -eq 0 ]]; then
    echo "Error: No .aiff files found in '$input_dir'."
    exit 1
fi
echo "$file_count files processed."
echo "Total duration: $((total_duration_ms / 1000)) seconds."
echo "-------------------------------------"

# --- Generate FFMPEG Metadata File ---
echo "Generating chapter metadata file content..."
# Use a block redirection for cleaner writing to the metadata file
{
    echo ";FFMETADATA1" # Header
    # Global Metadata
    [[ -n "$arg_title" ]] && echo "title=$arg_title"
    [[ -n "$arg_author" ]] && echo "artist=$arg_author"
    [[ -n "$arg_title" ]] && echo "album=$arg_title" # Often good to set album=title
    echo "genre=Audiobook"
    echo ""

    # Chapter Metadata
    num_chapters=${#chapter_times[@]}
    for (( i=0; i<$num_chapters; i++ )); do
        start_ms=${chapter_times[$i]}
        # Calculate end time (start of next chapter, or total duration for last chapter)
        if [[ $i -lt $((num_chapters - 1)) ]]; then
            end_ms=${chapter_times[$((i+1))]}
        else
            end_ms=$total_duration_ms
        fi
        title="${chapter_titles[$i]}" # Use the extracted title

        echo "[CHAPTER]"
        echo "TIMEBASE=1/1000" # Timebase in milliseconds
        echo "START=$start_ms"
        echo "END=$end_ms"
        echo "title=$title"
        echo ""
    done
} > "$metadata_file"

echo "Metadata content generated for: $metadata_file"
echo "Concat list content generated for: $concat_list_file"
echo "-------------------------------------"

# --- Build the Final FFMPEG Command Array ---
# This is done regardless of dry run mode to show/use the command
echo "Preparing ffmpeg command..."
ffmpeg_cmd=(ffmpeg
    -v warning -stats                  # Show progress/stats, less verbose logging
    -f concat -safe 0 -i "$concat_list_file" # Input via concat list (needs -safe 0 for relative paths if not using abs)
    -i "$metadata_file"               # Input metadata file
)
map_cover_idx=""
# Add cover art input if provided
if [[ -n "$arg_cover" ]]; then
    ffmpeg_cmd+=(-i "$arg_cover")
    map_cover_idx=2 # Cover art is the 3rd input (index 2), after concat list (0) and metadata (1)
fi

# Add stream mapping and codec settings
ffmpeg_cmd+=(
    -map_metadata 1                   # Apply metadata from the metadata file (input 1)
    -map 0:a                          # Map audio from the concatenated input (input 0)
)
# Add cover art mapping if present
if [[ -n "$map_cover_idx" ]]; then
     # Map the video stream from cover art input, copy codec, set as attached picture
     ffmpeg_cmd+=(-map "$map_cover_idx:v" -c:v copy -disposition:v attached_pic)
fi

# Add audio codec settings and output file
ffmpeg_cmd+=(
    -c:a aac -b:a "$arg_bitrate"      # Encode audio to AAC with specified bitrate
    -f mp4                            # Ensure MP4 container format (for .m4b)
    "$expanded_output_path"           # Use the potentially expanded output path
)

# --- Execute or Simulate Final Command ---
if $dry_run; then
    echo "*** DRY RUN MODE ***"
    echo "Actions that would be taken:"
    echo "1. Create concat list file ($concat_list_file) with content:"
    cat "$concat_list_file" | sed 's/^/   /' # Show indented content
    echo ""
    echo "2. Create metadata file ($metadata_file) with content:"
    cat "$metadata_file" | sed 's/^/   /' # Show indented content
    echo ""
    echo "3. Would execute the following ffmpeg command:"
    # Print the command elements clearly quoted for shell execution
    printf "   %q" "${ffmpeg_cmd[@]}"
    echo # Newline after command
    echo ""
    echo "Output file '$expanded_output_path' would NOT be created." # Use expanded path
    echo "*** END DRY RUN MODE ***"
    # Let the trap handle cleanup
else
    echo "Starting final encoding process (this may take a while)..."
    echo "Executing ffmpeg..."
    # echo "Debug Command: ${ffmpeg_cmd[@]}" # Uncomment to see the full command before execution
    if "${ffmpeg_cmd[@]}"; then
        echo "-------------------------------------"
        echo "Successfully created audiobook: $expanded_output_path" # Use expanded path
        echo "-------------------------------------"
    else
        exit_code=$?
        echo "-------------------------------------"
        echo "Error: ffmpeg encoding failed with exit code $exit_code."
        echo "Check ffmpeg output above for details."
        echo "-------------------------------------"
        # Let the trap handle cleanup, but exit with error code
        exit $exit_code
    fi
fi

# Cleanup is handled by the trap on exit
exit 0