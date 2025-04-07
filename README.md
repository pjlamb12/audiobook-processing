# Audio Processing Scripts

A collection of bash scripts designed to help copy, rename, package, and manage audio files, particularly useful for processing audiobook chapters ripped from CDs or other sources.

**Environment:** These scripts were developed and tested on macOS. They rely on common command-line tools like `bash`, `find`, `sort`, `tr`, `sed`, `basename`, `dirname`, `mv`, `rsync`, `mktemp`. The `create-m4b.sh` script additionally requires `ffmpeg` and `ffprobe`. Behavior might differ slightly on other Unix-like systems if tools have different versions or options (e.g., GNU vs. BSD utilities).

**Important Notes:**

-   **Make scripts executable:** Before running, use `chmod +x script_name.sh`.
-   **Use Dry Run First:** Most scripts include a dry run flag (`-N` or `-n`/`--dry-run`). **Always use this first** to review the intended actions before any files are actually copied, moved, or renamed.
-   **Back Up Originals:** It's highly recommended to back up your original audio files before running batch processing scripts.
-   **Filename Conventions:** The renaming scripts often expect filenames to start with track or chapter numbers for correct sorting (e.g., `001 Chapter One.aiff`, `Track 02 - Name.mp3`). The `create-m4b.sh` script (MP3 version) relies heavily on filenames sorting correctly using version sort.

---

## `copy-rename-cd.sh`

_(Implements Temp Directory + Sanitization Workflow)_

### Purpose

Copies audio files from a source directory (like a CD volume) into a final destination directory. During the process, it renames `.aiff` files matching a specific pattern (`NNN Text.aiff`) sequentially with 3-digit zero-padding and sanitizes the text portion of the filename. This uses a temporary directory for safety.

### Workflow

1.  Ensures the final destination directory exists.
2.  Creates a unique temporary directory _inside_ the final destination directory.
3.  **Copies** all files from the specified source directory into the temporary directory using `rsync`.
4.  **Scans** the temporary directory for `.aiff` files matching the pattern `Number Text.aiff`.
5.  **Sanitizes & Renames** matching files within the temporary directory:
    -   Sorts matched files naturally based on their original full name.
    -   Assigns a new sequential number (starting from `<start_num>`, padded to 3 digits: `001`, `002`...).
    -   Takes the original text part (after the number, before `.aiff`).
    -   Sanitizes the text part: keeps letters/numbers, converts spaces to single hyphens, removes other characters, trims leading/trailing hyphens.
    -   Constructs the new filename: `NNN-Sanitized-Text-Part.aiff`.
    -   Renames the file within the temporary directory.
6.  **Moves** all contents (renamed files and any other copied files) from the temporary directory up into the final destination directory using `rsync --remove-source-files`.
7.  Automatically **removes** the temporary directory upon completion or script interruption.

### Usage

```bash
./copy-rename-cd.sh -s <source_dir> -d <dest_dir> -n <start_num> [-N]
```

-   `-s <source_dir>`: Path to the source directory (e.g., `/Volumes/CD_NAME`) (required).
-   `-d <dest_dir>`: Path to the final destination directory (required, `~` expansion supported).
-   `-n <start_num>`: Starting number for the renaming sequence (required).
-   `-N`: Optional Dry run flag. Simulates copy, rename, and move without making actual changes.

---

## `rename-aiffs.sh`

_(In-Place Renaming)_

### Purpose

Renames existing `.aiff` files **within the current directory**. It identifies files starting with numbers, sorts them naturally, and renames them sequentially starting from a specified number, applying 3-digit zero-padding. _Does not sanitize filenames beyond renumbering._

### Workflow

1.  Scans the current directory for `.aiff` files.
2.  Sorts the found files naturally based on their original full filenames.
3.  Iterates through the sorted list.
4.  For each file matching the pattern `Number Text.aiff`:
    -   Generates a new sequential number (starting from `<start_num>`, padded to 3 digits).
    -   Extracts the original text part (including the `.aiff` extension).
    -   Constructs the new filename using the new number and the extracted text part.
    -   Renames the file in place.

### Usage

Run this script _while inside_ the directory containing the `.aiff` files you want to rename.

```bash
# cd /path/to/your/aiff/files
./rename-aiffs.sh [START_NUMBER] [--dry-run | -n]
```

-   `[START_NUMBER]`: Optional. The number to start the renaming sequence with. Defaults to `1` if omitted.
-   `--dry-run` or `-n`: Optional. Shows what renames would occur without actually changing any files.

---

## `rename-mp3s.sh`

_(In-Place Renaming for MP3 files)_

### Purpose

Renames existing `.mp3` files within the **current directory**. It identifies files starting with numbers, sorts them naturally, and renames them sequentially starting from a specified number, applying 3-digit zero-padding. _It does not sanitize the text part of the filename._

### Workflow

1.  Scans the current directory for `.mp3` files.
2.  Sorts the found files naturally based on their original full filenames.
3.  Iterates through the sorted list.
4.  For each file matching the pattern `Number Text.mp3` (or similar that sorts correctly):
    -   Generates a new sequential number (starting from `<start_num>`, padded to 3 digits: `001`, `002`...).
    -   Extracts the original text part (including the `.mp3` extension).
    -   Constructs the new filename using the new number and the extracted text part.
    -   Renames the file in place.

### Usage

Run this script _while inside_ the directory containing the `.mp3` files you want to rename.

```bash
# cd /path/to/your/mp3/files
./rename-mp3s.sh [START_NUMBER] [--dry-run | -n]
```

-   `[START_NUMBER]`: Optional. The number to start the renaming sequence with. Defaults to `1` if omitted.
-   `--dry-run` or `-n`: Optional. Shows what renames would occur without actually changing any files. **Highly recommended** to run this first.

### Key Assumptions

-   Operates only on `.mp3` files in the current directory.
-   Relies on `sort -V` (natural/version sort) of the original filenames to determine the order for renumbering. Ensure your files are named such that they sort correctly before running.
-   It primarily replaces the leading number based on sort order; it does not otherwise clean or sanitize the rest of the filename.

---

## `add-aiff-extension.sh`

_(Add Missing Extension)_

### Purpose

Checks files within the **current directory** and appends the `.aiff` extension to any non-hidden file that does not already have it (case-insensitive check). Useful for fixing files that lost their extension.

**Important Warning:** This script _assumes_ that any file lacking the `.aiff` extension _should_ be an AIFF file. It **does not** analyze file content. Running this on a directory containing other file types without extensions will incorrectly add `.aiff` to their names.

### Workflow

1.  Scans non-hidden files directly within the current directory.
2.  Checks if the filename ends with `.aiff` (case-insensitive).
3.  If the extension is missing:
    -   Constructs the new filename by appending `.aiff`.
    -   Checks if a file with the new name _already exists_. If it does, the original file is skipped to prevent overwriting.
    -   If the new name is safe, renames the original file.

### Usage

Run this script _while inside_ the directory containing the files needing the extension added.

```bash
# cd /path/to/files/missing/extension
# Run dry run first!
./add-aiff-extension.sh -n
# If looks good, run for real:
./add-aiff-extension.sh
```

-   `-n` or `--dry-run`: Optional. Shows which files would be renamed without actually changing files.

---

## `create-m4b.sh`

_(MP3 to M4B Audiobook Creation)_

### Purpose

Combines a sequence of sorted **MP3** files from an input directory into a single `.m4b` audiobook file, complete with chapter markers (based on filename stems), metadata, optional Series/Sequence info, and optional cover art.

### Dependencies

-   **`ffmpeg`** and **`ffprobe`**: Must be installed (e.g., `brew install ffmpeg`).

### Workflow

1.  Finds and **sorts `.mp3` files** in the input directory using **version sort** (relies on filenames like `PrefixPart01.mp3`, `PrefixPart02.mp3`, `PrefixPart10.mp3` sorting correctly).
2.  Uses `ffprobe` to get the duration of each MP3 file.
3.  Calculates start/end times for each chapter.
4.  Generates chapter metadata using the **filename stem** (e.g., "Darke-Part01") as the chapter title.
5.  Generates a temporary file list for `ffmpeg`.
6.  Uses `ffmpeg` to:
    -   Concatenate the audio from the input MP3 files.
    -   **Re-encode** the combined audio to **AAC format** (required for M4B).
    -   Inject the chapter metadata.
    -   Optionally add title, author, series name (`show` tag), and sequence number (`episode_id`/`track` tags) metadata.
    -   Optionally embed cover art.
    -   Package everything into an MP4 container, saved with the `.m4b` extension.
7.  Removes temporary files.

### Key Assumptions/Warnings

-   **Input Format:** Expects `.mp3` files. Use a different script version for `.aiff`.
-   **Sorting:** Critically relies on input filenames sorting correctly using `sort -V` (version sort) to ensure correct chapter order. Verify your filenames sort as expected.
-   **Chapter Titles:** Uses the filename without `.mp3` as the chapter title. Edit later if needed.
-   **Re-encoding:** Audio is re-encoded from MP3 to AAC, which is a lossy-to-lossy conversion. Use adequate bitrate (`-b`) to maintain quality.

### Usage

```bash
./create-m4b.sh -i <input_dir> -o <output_m4b> [-t <title>] [-a <author>] [-c <cover_art.jpg>] [-b <bitrate>] [-S <series_name>] [-E <sequence_num>] [-n]
```

-   `-i <input_dir>`: Directory containing the sorted MP3 chapter files (required).
-   `-o <output_m4b>`: Path for the output M4B file (required, `~` expansion supported).
-   `-t <title>`: Audiobook title metadata (optional).
-   `-a <author>`: Audiobook author/artist metadata (optional).
-   `-c <cover_art>`: Path to cover art image (jpg/png, optional).
-   `-b <bitrate>`: AAC audio bitrate (e.g., `96k`, `128k`, defaults to `128k`, optional).
-   `-S <series_name>`: Series Name metadata (optional).
-   `-E <sequence_num>`: Sequence number within series (optional).
-   `-n`: Optional Dry run flag. Shows steps and final `ffmpeg` command without executing it.

---

## `create-m4b-from-mp3.sh`

_(MP3 to M4B Audiobook Creation)_

### Purpose

Combines a sequence of sorted **MP3** files from an input directory into a single `.m4b` audiobook file, complete with chapter markers (based on filename stems), metadata, optional Series/Sequence info, and optional cover art.

### Dependencies

-   **`ffmpeg`** and **`ffprobe`**: Must be installed (e.g., on macOS via Homebrew: `brew install ffmpeg`).

### Workflow

1.  Finds and **sorts `.mp3` files** in the input directory using **version sort** (relies on filenames like `PrefixPart01.mp3`, `PrefixPart02.mp3`, `PrefixPart10.mp3` sorting correctly).
2.  Uses `ffprobe` to get the duration of each MP3 file.
3.  Calculates start/end times for each chapter.
4.  Generates chapter metadata using the **filename stem** (e.g., "Darke-Part01") as the chapter title.
5.  Generates a temporary file list for `ffmpeg`.
6.  Uses `ffmpeg` to:
    -   Concatenate the audio from the input MP3 files.
    -   **Re-encode** the combined audio to **AAC format** (required for M4B).
    -   Inject the chapter metadata.
    -   Optionally add title, author, series name (`show` tag), and sequence number (`episode_id`/`track` tags) metadata.
    -   Optionally embed cover art.
    -   Package everything into an MP4 container, saved with the `.m4b` extension.
7.  Removes temporary files.

### Key Assumptions/Warnings

-   **Input Format:** Expects `.mp3` files. Use a different script version for `.aiff`.
-   **Sorting:** Critically relies on input filenames sorting correctly using `sort -V` (version sort) to ensure correct chapter order. Verify your filenames sort as expected.
-   **Chapter Titles:** Uses the filename without `.mp3` as the chapter title. Edit later if needed.
-   **Re-encoding:** Audio is re-encoded from MP3 to AAC, which is a lossy-to-lossy conversion. Use adequate bitrate (`-b`) to maintain quality.

### Usage

```bash
./create-m4b-from-mp3.sh -i <input_dir> -o <output_m4b> [-t <title>] [-a <author>] [-c <cover_art.jpg>] [-b <bitrate>] [-S <series_name>] [-E <sequence_num>] [-n]
```

-   `-i <input_dir>`: Directory containing the sorted MP3 chapter files (required).
-   `-o <output_m4b>`: Path for the output M4B file (required, `~` expansion supported).
-   `-t <title>`: Audiobook title metadata (optional).
-   `-a <author>`: Audiobook author/artist metadata (optional).
-   `-c <cover_art>`: Path to cover art image (jpg/png, optional).
-   `-b <bitrate>`: AAC audio bitrate (e.g., `96k`, `128k`, defaults to `128k`, optional).
-   `-S <series_name>`: Series Name metadata (optional).
-   `-E <sequence_num>`: Sequence number within series (optional).
-   `-n`: Optional Dry run flag. Shows steps and final `ffmpeg` command without executing it.

---

## `sanitize-filenames.sh`

_(In-Place Filename Sanitization)_

### Purpose

Renames files within the **current directory** to remove or replace characters that can sometimes cause issues in file systems or URLs. It keeps letters and numbers, converts spaces to single hyphens, collapses multiple hyphens, removes other characters, and preserves file extensions.

### Workflow

1.  Scans non-hidden files directly within the current directory.
2.  Separates the filename stem (name before the last dot) and the extension.
3.  Processes the stem:
    -   Replaces spaces with hyphens.
    -   Removes all characters that are not alphanumeric (`a-z, A-Z, 0-9`) or a hyphen (`-`).
    -   Collapses any resulting sequences of multiple hyphens into a single hyphen.
    -   Trims any leading or trailing hyphens.
4.  Reconstructs the new filename using the sanitized stem and the original extension.
5.  Checks if the new filename already exists (and is different from the original). Skips if it exists to prevent overwriting.
6.  Checks if the filename actually changed. Skips if no change is needed.
7.  Checks if the sanitized stem became empty. Skips if it did.
8.  Renames the original file to the new sanitized filename.

### Usage

Run this script _while inside_ the directory containing the files you want to sanitize.

```bash
# cd /path/to/your/files/to/sanitize
# Run dry run first!
./sanitize-filenames.sh -n
# or
./sanitize-filenames.sh --dry-run

# If dry run looks correct, run for real:
./sanitize-filenames.sh
```

-   `-n` or `--dry-run`: Optional. Shows which files would be renamed without actually changing any files. **Highly recommended** to run this first.

---

## Tips

-   Sometimes, when you first insert an audio CD on macOS, the mounted volume name might be generic (like "Audio CD" or "Disc Drive"). It's been observed that **opening the macOS Music app** after inserting the disc can trigger the system to recognize the actual disc title (e.g., "My Audiobook Title") as the volume name. The Music app may also fetch track names from an online database (like Gracenote). Waiting for this to happen before running `copy-rename-cd.sh` can be helpful, as it gives you the correct volume name to use for the `-s` argument and provides the actual track names as a reference in case the automatic renaming based on numbers needs adjustment later.

---
