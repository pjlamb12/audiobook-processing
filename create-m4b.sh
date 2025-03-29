#!/bin/bash

# --- Script to create M4B audiobook from sorted AIFF files ---
# --- Includes Chapters, Metadata, Cover Art, Series/Sequence ---

# --- Script Configuration ---
DEFAULT_BITRATE="128k" # Default AAC bitrate (e.g., 96k, 128k, 192k)

# --- Function Definitions ---
usage() {
  echo "Usage: $0 -i <input_dir> -o <output_m4b> [-t <title>] [-a <author>] [-c <cover_art.jpg>] [-b <bitrate>] [-S <series_name>] [-E <sequence_num>] [-n]"
  echo "  -i <input_dir>    : Directory containing sorted AIFF files (required)."
  echo "  -o <output_m4b>   : Path for the output M4B file (required, '~' expansion supported)."
  echo "  -t <title>        : Audiobook title metadata (optional)."
  echo "  -a <author>       : Audiobook author/artist metadata (optional)."
  echo "  -c <cover_art>    : Path to cover art image (jpg/png, optional)."
  echo "  -b <bitrate>      : AAC audio bitrate (e.g., 96k, 128k, default: ${DEFAULT_BITRATE}, optional)."
  echo "  -S <series_name>  : Series Name metadata (optional, uses 'show' tag)."
  echo "  -E <sequence_num> : Sequence number within series (optional, uses 'episode_id' tag)."
  echo "  -n                : Dry run. Perform all steps except final encoding, show command."
  echo "  -h                : Show this help message."
  exit 1
}

# Function to clean up temporary files
cleanup() {
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
arg_series=""    # New variable for Series Name
arg_sequence=""  # New variable for Series Sequence
dry_run=false

concat_list_file=""
metadata_file=""

# Added S: and E: to getopt string
while getopts "hni:o:t:a:c:b:S:E:" opt; do
  case $opt in
    h) usage ;;
    n) dry_run=true ;;
    i) input_dir="$OPTARG" ;;
    o) output_m4b="$OPTARG" ;;
    t) arg_title="$OPTARG" ;;
    a) arg_author="$OPTARG" ;;
    c) arg_cover="$OPTARG" ;;
    b) arg_bitrate="$OPTARG" ;;
    S) arg_series="$OPTARG" ;;   # Capture Series Name
    E) arg_sequence="$OPTARG" ;; # Capture Sequence Number
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# --- Validate Inputs ---
if [[ -z "$input_dir" ]] || [[ -z "$output_m4b" ]]; then
  echo "Error: Input directory (-i) and output file (-o) are required."
  usage
fi
if [[ ! -d "$input_dir" ]]; then
  echo "Error: Input directory '$input_dir' not found."
  exit 1
fi
if [[ -n "$arg_cover" ]] && [[ ! -f "$arg_cover" ]]; then
  echo "Error: Cover art file '$arg_cover' not found."
  exit 1
fi
# Optional: Validate sequence number is an integer if provided
if [[ -n "$arg_sequence" ]] && ! [[ "$arg_sequence" =~ ^[0-9]+$ ]]; then
    echo "Error: Sequence number (-E) must be an integer."
    exit 1
fi
if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null; then
    echo "Error: 'ffmpeg' or 'ffprobe' command not found."
    echo "Please install ffmpeg (e.g., 'brew install ffmpeg')."
    exit 1
fi

# --- Expand Tilde (~) in Output Path ---
expanded_output_path="$output_m4b"
if [[ "${output_m4b:0:1}" == "~" ]]; then
    expanded_output_path="$HOME${output_m4b:1}"
    echo "Info: Expanded output path '~' to '$HOME'."
fi

# --- Check if Output Directory Exists ---
output_dir=$(dirname "$expanded_output_path")
if [[ ! -d "$output_dir" ]]; then
    echo "Error: Output directory '$output_dir' does not exist."
    echo "Please create the directory first or specify a different output path."
    exit 1
fi

# --- Prepare for Processing ---
trap cleanup EXIT SIGINT SIGTERM # Set trap for cleanup

if $dry_run; then echo "*** DRY RUN MODE ENABLED ***"; fi
echo "Starting Audiobook Creation Process..."
echo "Input Directory: $input_dir"
echo "Output File: $expanded_output_path"
[[ -n "$arg_title" ]] && echo "Title: $arg_title"
[[ -n "$arg_author" ]] && echo "Author: $arg_author"
[[ -n "$arg_series" ]] && echo "Series: $arg_series"        # Display series if set
[[ -n "$arg_sequence" ]] && echo "Sequence: $arg_sequence"  # Display sequence if set
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
unset chapter_times chapter_titles
total_duration_ms=0
file_count=0

while IFS= read -r -d $'\0' file; do
    # ... (rest of the file processing loop remains the same - ffprobe, title extraction, etc) ...
    file_count=$((file_count + 1))
    filename=$(basename "$file")
    echo "Processing: $filename"

    abs_path=$(cd "$(dirname "$file")" && pwd)/$(basename "$file")
    echo "file '${abs_path//\'/\'\\\'\'}'" >> "$concat_list_file"

    duration_s=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file")
    if [[ -z "$duration_s" ]]; then
        echo "Error: Could not get duration for '$filename'. Aborting."
        exit 1
    fi
    duration_ms=$(awk -v dur="$duration_s" 'BEGIN{printf "%.0f", dur * 1000}')

    chapter_times+=($total_duration_ms)

    if [[ "$filename" =~ ^[0-9]+[[:space:]]*[-[:space:]]*(.*)\.aiff$ ]]; then
         title="${BASH_REMATCH[1]}"
         title=$(echo "$title" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
         title="${filename%.*}"
    fi
    chapter_titles+=("$title")
    echo "  -> Chapter Title: '$title', Start: ${total_duration_ms}ms, Duration: ${duration_ms}ms"

    total_duration_ms=$((total_duration_ms + duration_ms))

done < <(find "$input_dir" -maxdepth 1 -name "*.aiff" -print0 | sort -zV)

if [[ $file_count -eq 0 ]]; then
    echo "Error: No .aiff files found in '$input_dir'."
    exit 1
fi
echo "$file_count files processed."
echo "Total duration: $((total_duration_ms / 1000)) seconds."
echo "-------------------------------------"

# --- Generate FFMPEG Metadata File (for chapters) ---
echo "Generating chapter metadata file content..."
{
    echo ";FFMETADATA1"
    # Global Metadata (Basic - Title/Artist/Album/Genre set here)
    # Additional metadata like Series/Sequence added directly in ffmpeg command
    [[ -n "$arg_title" ]] && echo "title=$arg_title"
    [[ -n "$arg_author" ]] && echo "artist=$arg_author"
    [[ -n "$arg_title" ]] && echo "album=$arg_title"
    echo "genre=Audiobook"
    echo ""

    # Chapter Metadata
    num_chapters=${#chapter_times[@]}
    for (( i=0; i<$num_chapters; i++ )); do
        start_ms=${chapter_times[$i]}
        if [[ $i -lt $((num_chapters - 1)) ]]; then end_ms=${chapter_times[$((i+1))]}; else end_ms=$total_duration_ms; fi
        title="${chapter_titles[$i]}"
        echo "[CHAPTER]"; echo "TIMEBASE=1/1000"; echo "START=$start_ms"; echo "END=$end_ms"; echo "title=$title"; echo ""
    done
} > "$metadata_file"

echo "Metadata file generated: $metadata_file"
echo "Concat list file generated: $concat_list_file"
echo "-------------------------------------"

# --- Build the Final FFMPEG Command Array ---
echo "Preparing ffmpeg command..."
ffmpeg_cmd=(ffmpeg -v warning -stats -f concat -safe 0 -i "$concat_list_file" -i "$metadata_file")
map_cover_idx=""
if [[ -n "$arg_cover" ]]; then
    ffmpeg_cmd+=(-i "$arg_cover")
    map_cover_idx=2
fi
ffmpeg_cmd+=(-map_metadata 1 -map 0:a)
if [[ -n "$map_cover_idx" ]]; then
     ffmpeg_cmd+=(-map "$map_cover_idx:v" -c:v copy -disposition:v attached_pic)
fi

# --- ADDED METADATA FLAGS ---
# Add Series Name if provided (using 'show' key)
if [[ -n "$arg_series" ]]; then
    ffmpeg_cmd+=(-metadata "show=$arg_series")
fi
# Add Sequence Number if provided (using 'episode_id' key)
# Also adding as 'track' can sometimes help with sorting in players
if [[ -n "$arg_sequence" ]]; then
    ffmpeg_cmd+=(-metadata "episode_id=$arg_sequence")
    # Optional: Add track number as well. You might need total tracks for TN/TT format.
    # For simplicity, just setting track = sequence number.
    ffmpeg_cmd+=(-metadata "track=$arg_sequence")
fi
# --- END ADDED METADATA FLAGS ---

# Add audio codec settings and output file (MUST BE LAST in this segment)
ffmpeg_cmd+=(
    -c:a aac -b:a "$arg_bitrate"
    -f mp4
    "$expanded_output_path"
)

# --- Execute or Simulate Final Command ---
if $dry_run; then
    echo "*** DRY RUN MODE ***"
    echo "Actions that would be taken:"
    echo "1. Create concat list file ($concat_list_file) with content:"
    cat "$concat_list_file" | sed 's/^/   /'
    echo ""
    echo "2. Create metadata file ($metadata_file) with content:"
    cat "$metadata_file" | sed 's/^/   /'
    echo ""
    echo "3. Would execute the following ffmpeg command:"
    printf "   %q" "${ffmpeg_cmd[@]}"
    echo; echo ""
    echo "Output file '$expanded_output_path' would NOT be created."
    echo "*** END DRY RUN MODE ***"
else
    echo "Starting final encoding process (this may take a while)..."
    echo "Executing ffmpeg..."
    # echo "Debug Command: ${ffmpeg_cmd[@]}"
    if "${ffmpeg_cmd[@]}"; then
        echo "-------------------------------------"
        echo "Successfully created audiobook: $expanded_output_path"
        echo "-------------------------------------"
    else
        exit_code=$?
        echo "-------------------------------------"
        echo "Error: ffmpeg encoding failed with exit code $exit_code."
        echo "Check ffmpeg output above for details."
        echo "-------------------------------------"
        exit $exit_code
    fi
fi

# Cleanup is handled by the trap on exit
exit 0