# Audio Processing Scripts

A collection of bash scripts designed to help copy, rename, and package audio files, particularly useful for processing audiobook chapters ripped from CDs or other sources as AIFF files.

**Important:**

-   Make scripts executable before running: `chmod +x script_name.sh`
-   **Always use the dry-run option first** (`-N` or `-n`/`--dry-run`) to verify the intended actions before making actual changes.
-   It's highly recommended to back up your original audio files before running batch processing scripts.
-   These scripts generally expect audio filenames to start with track/chapter numbers for correct sorting and renaming (e.g., `1 Chapter One.aiff`, `02 Chapter Two.aiff`, `10 Chapter Ten.aiff`).

---

## `copy-rename-cd.sh`

### Purpose

Copies audio files (e.g., `.aiff`) from a source directory (like a CD volume) into a final destination directory, renaming the files sequentially with 3-digit zero-padding during the process using a temporary directory workflow.

### Workflow

1.  Ensures the final destination directory exists.
2.  Creates a unique temporary directory _inside_ the final destination directory.
3.  **Copies** all files from the specified source directory into the temporary directory using `rsync`.
4.  **Renames** `.aiff` files found _within the temporary directory_. It expects filenames starting with numbers, sorts them naturally, and renames them sequentially starting from `<start_num>`, applying 3-digit zero-padding (e.g., `001`, `002`, ..., `099`, `100`).
5.  **Moves** all contents from the temporary directory up into the final destination directory using `rsync --remove-source-files`.
6.  Automatically **removes** the temporary directory upon completion or script interruption.

### Usage

```bash
./copy_rename_cd.sh -s <source_dir> -d <dest_dir> -n <start_num> [-N]
```

-   `-s <source_dir>`: Path to the source directory (e.g., `/Volumes/CD_NAME`) (required).
-   `-d <dest_dir>`: Path to the final destination directory (required, `~` expansion supported).
-   `-n <start_num>`: Starting number for the renaming sequence (required).
-   `-N`: Optional Dry run flag. Simulates copy, rename, and move without making actual changes.

---

## `rename-aiffs.sh`

### Purpose

Renames existing `.aiff` files within the **current directory**. It identifies files starting with numbers, sorts them naturally, and renames them sequentially starting from a specified number, applying 3-digit zero-padding.

### Workflow

1.  Scans the current directory for `.aiff` files matching the pattern `NNN... Chapter Title.aiff`.
2.  Sorts the found files naturally based on their leading numbers.
3.  Iterates through the sorted list.
4.  For each file, generates a new sequential number (starting from `<start_num>`, padded to 3 digits).
5.  Constructs the new filename using the new number and the rest of the original filename (after the first space).
6.  Renames the file in place.

### Usage

Run this script _while inside_ the directory containing the `.aiff` files you want to rename.

```bash
./rename_aiffs.sh [START_NUMBER] [--dry-run | -n]
```

-   `[START_NUMBER]`: Optional. The number to start the renaming sequence with. Defaults to `1` if omitted.
-   `--dry-run` or `-n`: Optional. Shows what renames would occur without actually changing any files.

---

## `create-m4b.sh`

### Purpose

Combines a sequence of sorted audio files (presumably `.aiff` chapters) from an input directory into a single `.m4b` audiobook file, complete with chapter markers, metadata, and optional cover art.

### Dependencies

-   **`ffmpeg`** and **`ffprobe`**: These command-line tools must be installed. On macOS, you can usually install them via Homebrew: `brew install ffmpeg`.

### Workflow

1.  Finds and naturally sorts `.aiff` files in the specified input directory.
2.  Uses `ffprobe` to get the duration of each file.
3.  Calculates start and end times for each chapter based on file durations.
4.  Generates a temporary `ffmpeg` metadata file containing chapter titles (extracted from filenames) and timings.
5.  Generates a temporary file list for `ffmpeg`'s concat function.
6.  Uses `ffmpeg` to:
    -   Concatenate the audio from the input files.
    -   Encode the combined audio to AAC format using a specified bitrate.
    -   Inject the chapter metadata.
    -   Optionally add title, author/artist metadata.
    -   Optionally embed cover art.
    -   Package everything into an MP4 container, saved with the `.m4b` extension.
7.  Removes temporary files.

### Usage

```bash
./create_m4b.sh -i <input_dir> -o <output_m4b> [-t <title>] [-a <author>] [-c <cover_art.jpg>] [-b <bitrate>] [-n]
```

-   `-i <input_dir>`: Directory containing the sorted AIFF chapter files (required).
-   `-o <output_m4b>`: Path for the output M4B file (required, `~` expansion supported).
-   `-t <title>`: Audiobook title metadata (optional).
-   `-a <author>`: Audiobook author/artist metadata (optional).
-   `-c <cover_art>`: Path to cover art image (jpg/png, optional).
-   `-b <bitrate>`: AAC audio bitrate (e.g., `96k`, `128k`, defaults to `128k`, optional).
-   `-n`: Optional Dry run flag. Performs steps up to generating temp files and shows the final `ffmpeg` command without executing it.
