#!/bin/bash

## ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****
## *    gdrive_download.sh 
## *    Created by: Hugo Gaibor
## *    Date: 2026-07-31
## *    License: GNU/GPL3+
## *
## *    Usage:
## *      . gdrive_download.sh [--fileid="<FILE_ID>" | --url="<URL>"] [--filename=<FILENAME>] [--detach]
## *       
## *      (run `chmod +x gdrive_download.sh` previously) 
## *      ./gdrive_download.sh [--fileid="<FILE_ID>" | --url="<URL>"] [--filename=<FILENAME>] [--detach]
## *       
## *      IMPORTANT: In order for the script to work, the file's shared permissions need
## *                 to allow the file to be downloaded publicly with no google login required.
## *       
## *                 To prevent URL characters to be trimmed by bash, wrap the URL or FileId in quotes.
## *       
## *    Parameters: 
## *      **either fileid or url are required**
## *      - fileid:    Google Drive ID of the file from the URL.
## *      - url:       Full Google Drive share link (automatically extracts the file ID).
## *      - filename:  (Optional) name of the file and extension to store the file locally.
## *                   If the file is saved as 'unspecified' or some with an odd name,
## *                   use this parameter explicitly.
## *      - detach:    (Optional) can launch the download in a background tmux session to allow
## *                   SSH client to be closed without interrupting download
## *      
## *      This script will download files shared publicly on Google Drive automatically.  
## *      Useful to run from a server via SSH when a customer has provided a backup file and  
## *      you don't want to get download it on your PC, then upload it via WebGUI / SCP to 
## *      get it to the server. 
## *        
## *      It will work on both small files and large files that require to confirm to download  
## *        
## ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****

# Initialize variables
FILE_ID=""
URL=""
FILENAME=""
DETACH=false

# Parse named parameters
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --fileid) FILE_ID="$2"; shift 2 ;;
        --fileid=*) FILE_ID="${1#*=}"; shift 1 ;;
        --url) URL="$2"; shift 2 ;;
        --url=*) URL="${1#*=}"; shift 1 ;;
        --filename) FILENAME="$2"; shift 2 ;;
        --filename=*) FILENAME="${1#*=}"; shift 1 ;;
        --detach) DETACH=true; shift 1 ;;
        *)
            echo "Error: Unknown parameter passed: $1"
            echo "Usage: $0 [--fileid=<FILE_ID> | --url=<URL>] [--filename=<FILENAME>] [--detach]"
            return 1 2>/dev/null || exit 1
            ;;
    esac
done

# Extract File ID from URL if provided
if [[ -n "$URL" ]]; then
    # Match format: https://drive.google.com/file/d/FILE_ID/view
    if [[ "$URL" =~ /d/([a-zA-Z0-9_-]+) ]]; then
        FILE_ID="${BASH_REMATCH[1]}"
    # Match format: https://drive.google.com/open?id=FILE_ID
    elif [[ "$URL" =~ id=([a-zA-Z0-9_-]+) ]]; then
        FILE_ID="${BASH_REMATCH[1]}"
    else
        echo "Error: Could not extract a valid Google Drive File ID from the provided URL."
        return 1 2>/dev/null || exit 1
    fi
fi

# Validate that the file ID is provided
if [[ -z "$FILE_ID" ]]; then
    echo "Error: Either --fileid or --url must be provided."
    echo "Usage: $0 [--fileid=\"<FILE_ID>\" | --url=\"<URL>\"] [--filename=<FILENAME>] [--detach]"
    return 1 2>/dev/null || exit 1
fi

# If detach is requested, verify tmux is installed
if [[ "$DETACH" == true ]] && ! command -v tmux &> /dev/null; then
    echo "Error: 'tmux' is not installed but --detach was requested."
    return 1 2>/dev/null || exit 1
fi

# Generate the smart runner script that handles both small and large files
RUNNER_SCRIPT=$(mktemp)

cat << 'EOF' > "$RUNNER_SCRIPT"
#!/bin/bash
FILE_ID="$1"
FILENAME="$2"
DETACH_MODE="$3"
ORIG_DIR="$PWD"
TMP_DIR=$(mktemp -d)

# Move into isolated directory to prevent curl from overwriting local files
cd "$TMP_DIR" || exit 1
COOKIE_FILE="cookies.txt"

echo "Contacting Google Drive for File ID: $FILE_ID..."

# Step 1: Attempt the initial download
if [[ -n "$FILENAME" ]]; then
    curl -s -c "$COOKIE_FILE" -L -o "$FILENAME" "https://drive.google.com/uc?export=download&id=$FILE_ID"
    TARGET_FILE="$FILENAME"
else
    curl -s -c "$COOKIE_FILE" -L -J -O "https://drive.google.com/uc?export=download&id=$FILE_ID"
    TARGET_FILE=$(ls -1 | grep -v "$COOKIE_FILE" | head -n 1)
fi

if [[ -z "$TARGET_FILE" || ! -f "$TARGET_FILE" ]]; then
    echo "Error: Failed to download anything from Google Drive."
    cd "$ORIG_DIR" && rm -rf "$TMP_DIR" && rm -f "$0"
    exit 1
fi

# Step 2: Check if the downloaded file is the HTML virus warning page
# We use grep -a to treat the file as text in case grep gets confused by binaries
if grep -aq '<title>Google Drive - Virus scan warning</title>' "$TARGET_FILE"; then
    echo "Large file detected. Bypassing virus scan warning..."
    
    # Extract tokens from the warning page
    CONFIRM=$(grep -ao 'name="confirm" value="[^"]*"' "$TARGET_FILE" | head -n 1 | cut -d'"' -f4)
    UUID=$(grep -ao 'name="uuid" value="[^"]*"' "$TARGET_FILE" | head -n 1 | cut -d'"' -f4)
    
    # Delete the HTML warning page
    rm -f "$TARGET_FILE"
    
    # Step 3: Run the real download using the extracted tokens
    if [[ -n "$FILENAME" ]]; then
        curl -L -b "$COOKIE_FILE" -o "$FILENAME" "https://drive.usercontent.google.com/download?id=${FILE_ID}&export=download&confirm=${CONFIRM}&uuid=${UUID}"
        mv "$FILENAME" "$ORIG_DIR/"
        echo ""
        echo "[OK] Download completed successfully!"
        echo "Saved as: $FILENAME"
    else
        curl -L -b "$COOKIE_FILE" -J -O "https://drive.usercontent.google.com/download?id=${FILE_ID}&export=download&confirm=${CONFIRM}&uuid=${UUID}"
        FINAL_FILE=$(ls -1 | grep -v "$COOKIE_FILE" | head -n 1)
        mv "$FINAL_FILE" "$ORIG_DIR/"
        echo ""
        echo "[OK] Download completed successfully!"
        echo "Saved as: $FINAL_FILE"
    fi
else
    # If the file lacks the warning title, it's a small file and already finished downloading!
    echo "Small file detected. Downloaded successfully on first attempt!"
    mv "$TARGET_FILE" "$ORIG_DIR/"
    echo ""
    echo "[OK] Download completed successfully!"
    echo "Saved as: $TARGET_FILE"
fi

# Cleanup temporary directory
cd "$ORIG_DIR" || exit 1
rm -rf "$TMP_DIR"

# Pause before closing if running inside tmux
if [[ "$DETACH_MODE" == "true" ]]; then
    echo ""
    echo "Press any key to close this session window."
    read -n 1 -s
fi

# Self-destruct the runner script
rm -f "$0"
EOF

# Make the runner script executable
chmod +x "$RUNNER_SCRIPT"

# Execute the runner script based on user preference
if [[ "$DETACH" == true ]]; then
    SESSION_NAME="gdrive_${FILE_ID:0:6}"
    echo "Starting background download in tmux session: $SESSION_NAME"
    
    # Launch in tmux safely
    tmux new-session -d -s "$SESSION_NAME" "bash '$RUNNER_SCRIPT' '$FILE_ID' '$FILENAME' 'true'"
    
    echo "Success! You can safely exit SSH."
    echo "To check progress later, run: tmux attach -t $SESSION_NAME"
else
    # Run normally in the foreground
    bash "$RUNNER_SCRIPT" "$FILE_ID" "$FILENAME" "false"
fi