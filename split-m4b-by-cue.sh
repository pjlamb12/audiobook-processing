#!/bin/bash

# --- Script to split a large M4B and its CUE sheet into multiple books ---
# --- v2: Fixes floating point arithmetic and improves CUE parsing logic ---

# --- Function Definitions ---
usage() {
  echo "Usage: $0 <directory> <start_tracks>"
  echo "  Splits a single M4B/CUE file into multiple books."
  echo ""
  echo "  <directory>      : Path to the directory containing one .m4b and one .cue file (required)."
  echo "  <start_tracks>   : Comma-separated list of track numbers that start each new book (e.g., '1,15,28')."
  echo "  -h               : Show this help message."
  exit 1
}

# Function to convert MM:SS:FF format to total milliseconds
time_to_ms() {
    local time_str=$1
    # Use awk for all floating point math to get an integer result
    echo "$time_str" | awk -F'[:]' '{ printf "%.0f", ($1 * 60 + $2) * 1000 + ($3 * 1000 / 75) }'
}

# Function to convert total milliseconds to MM:SS:FF format
ms_to_time() {
    local total_ms=$1
    # Use awk for all floating point math
    awk -v total_ms="$total_ms" 'BEGIN {
        ms = total_ms % 1000;
        total_seconds = int(total_ms / 1000);
        seconds = total_seconds % 60;
        minutes = int(total_seconds / 60);
        frames = int(ms / (1000/75));
        printf "%02d:%02d:%02d", minutes, seconds, frames;
    }'
}

# Function to convert total milliseconds to HH:MM:SS.ms for ffmpeg
ms_to_ffmpeg_time() {
    local total_ms=$1
    # Use awk for all floating point math
    awk -v total_ms="$total_ms" 'BEGIN {
        ms = total_ms % 1000;
        total_seconds = int(total_ms / 1000);
        seconds = total_seconds % 60;
        total_minutes = int(total_seconds / 60);
        minutes = total_minutes % 60;
        hours = int(total_minutes / 60);
        printf "%02d:%02d:%02d.%03d", hours, minutes, seconds, ms;
    }'
}

# --- Argument Parsing & Validation ---
if [[ "$1" == "-h" || -z "$1" || -z "$2" ]]; then
    usage
fi

input_dir="$1"
start_tracks_csv="$2"

if [[ ! -d "$input_dir" ]]; then echo "Error: Input directory '$input_dir' not found." >&2; exit 1; fi
if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null; then echo "Error: 'ffmpeg' or 'ffprobe' not found." >&2; echo "Install: brew install ffmpeg"; exit 1; fi

m4b_file=$(find "$input_dir" -maxdepth 1 -type f -iname "*.m4b")
cue_file=$(find "$input_dir" -maxdepth 1 -type f -iname "*.cue")

if [[ -z "$m4b_file" || -z "$cue_file" ]]; then echo "Error: Directory must contain one .m4b file and one .cue file." >&2; exit 1; fi

echo "Source M4B: $m4b_file"
echo "Source CUE: $cue_file"
echo "-------------------------------------"

# --- Parse CUE file into arrays ---
echo "Parsing CUE file..."
declare -a CUE_TRACK_NUMS
declare -a CUE_TITLES
declare -a CUE_START_TIMES_MS

# Read CUE file line by line
track_num=""
track_title=""
while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r') # Remove carriage returns
    if [[ "$line" =~ TRACK[[:space:]]+([0-9]+) ]]; then track_num="${BASH_REMATCH[1]}"; fi
    if [[ "$line" =~ TITLE[[:space:]]+\"(.*)\" ]]; then track_title="${BASH_REMATCH[1]}"; fi
    if [[ "$line" =~ INDEX[[:space:]]+01[[:space:]]+([0-9]+:[0-9]{2}:[0-9]{2}) ]]; then
        start_time="${BASH_REMATCH[1]}"
        if [[ -n "$track_num" && -n "$track_title" ]]; then
            CUE_TRACK_NUMS+=("$track_num")
            CUE_TITLES+=("$track_title")
            CUE_START_TIMES_MS+=("$(time_to_ms "$start_time")")
            track_num=""; track_title="" # Reset for next track
        fi
    fi
done < "$cue_file"

total_tracks=${#CUE_TRACK_NUMS[@]}
echo "Found $total_tracks tracks in CUE file."
if [[ $total_tracks -eq 0 ]]; then echo "Error: No valid tracks found."; exit 1; fi

# --- Prepare Book Splitting ---
IFS=',' read -r -a START_TRACKS <<< "$start_tracks_csv"
START_TRACKS+=($((total_tracks + 1))) # Add end marker
num_books=$((${#START_TRACKS[@]} - 1))

echo "Planning to split into $num_books book(s)..."
echo "-------------------------------------"

# --- Main Splitting Loop ---
for (( i=0; i<$num_books; i++ )); do
    book_num=$((i + 1))
    start_track=${START_TRACKS[$i]}
    end_track=$((${START_TRACKS[$((i+1))]} - 1))
    
    start_index=$((start_track - 1))
    end_index=$((end_track - 1))

    # Get book name from first chapter title and sanitize it
    book_name_raw="${CUE_TITLES[$start_index]}"
    # Clean up title like "3: Threats" to just "Threats"
    book_name_clean=$(echo "$book_name_raw" | sed -E 's/^[0-9]+:[[:space:]]*//')
    book_name_sanitized=$(echo "$book_name_clean" | tr ' ' '-' | tr -cd '[:alnum:]-' | tr -s '-' | sed -e 's/^-//' -e 's/-$//')
    if [[ -z "$book_name_sanitized" ]]; then book_name_sanitized="Book-${book_num}"; fi
    # Prepend Book number for sorting
    final_book_name="Book-${book_num}-${book_name_sanitized}"

    output_m4b_path="$input_dir/${final_book_name}.m4b"
    output_cue_path="$input_dir/${final_book_name}.cue"
    ffmpeg_meta_file=$(mktemp /tmp/ffmpeg_metadata.XXXXXX)
    
    trap "rm -f '$ffmpeg_meta_file'" RETURN # Cleanup temp file

    echo "Processing Book #$book_num: '$book_name_clean' (Tracks $start_track - $end_track)"
    echo "  -> Output M4B: $output_m4b_path"

    # --- Determine Timings ---
    book_start_time_ms=${CUE_START_TIMES_MS[$start_index]}

    if [[ $((i + 1)) -ge $num_books ]]; then # This is the last book
        echo "  -> Calculating total M4B duration for end time..."
        total_duration_s=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$m4b_file")
        book_end_time_ms=$(awk -v dur="$total_duration_s" 'BEGIN { printf "%.0f", dur * 1000 }')
    else # Not the last book
        next_book_start_index=$((${START_TRACKS[$((i+1))]} - 1))
        book_end_time_ms=${CUE_START_TIMES_MS[$next_book_start_index]}
    fi

    ffmpeg_start_time=$(ms_to_ffmpeg_time "$book_start_time_ms")
    ffmpeg_end_time=$(ms_to_ffmpeg_time "$book_end_time_ms")
    echo "  -> Splitting from $ffmpeg_start_time to $ffmpeg_end_time"

    # --- Generate New CUE and FFMPEG Metadata ---
    echo "  -> Generating new CUE and Chapter metadata..."
    { echo ";FFMETADATA1"; echo "title=$book_name_clean"; echo "album=$book_name_clean"; echo "track=$book_num"; echo "genre=Audiobook"; echo ""; } > "$ffmpeg_meta_file"
    { echo "TITLE \"$book_name_clean\""; echo "FILE \"${final_book_name}.m4b\" MP4"; } > "$output_cue_path"

    new_track_num=1
    for (( j=$start_index; j<=$end_index; j++ )); do
        relative_start_ms=$(awk -v current="${CUE_START_TIMES_MS[$j]}" -v start="$book_start_time_ms" 'BEGIN { print current - start }')
        
        if [[ $j -lt $end_index ]]; then
            relative_end_ms=$(awk -v next="${CUE_START_TIMES_MS[$((j+1))]}" -v start="$book_start_time_ms" 'BEGIN { print next - start }')
        else
            relative_end_ms=$(awk -v book_end="$book_end_time_ms" -v book_start="$book_start_time_ms" 'BEGIN { print book_end - book_start }')
        fi

        { echo "  TRACK $(printf "%02d" $new_track_num) AUDIO"; echo "    TITLE \"${CUE_TITLES[$j]}\""; echo "    INDEX 01 $(ms_to_time "$relative_start_ms")"; } >> "$output_cue_path"
        { echo "[CHAPTER]"; echo "TIMEBASE=1/1000"; echo "START=$relative_start_ms"; echo "END=$relative_end_ms"; echo "title=${CUE_TITLES[$j]}"; echo ""; } >> "$ffmpeg_meta_file"
        
        new_track_num=$((new_track_num + 1))
    done

    # --- Run FFMPEG Command ---
    echo "  -> Creating M4B file with chapters..."
    ffmpeg -y -hide_banner -v error \
           -i "$m4b_file" \
           -i "$ffmpeg_meta_file" \
           -ss "$ffmpeg_start_time" \
           -to "$ffmpeg_end_time" \
           -map 0:a \
           -map_metadata 1 \
           -map_metadata:s:a 0:s:a \
           -map 0:v? \
           -c copy \
           "$output_m4b_path"

    if [[ $? -eq 0 ]]; then echo "  -> Successfully created '$output_m4b_path'"; else echo "  -> ERROR: ffmpeg failed to create M4B for Book #$book_num."; fi
    rm -f "$ffmpeg_meta_file"
    echo "-------------------------------------"
done

echo "Script finished."
exit 0