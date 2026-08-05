#!/bin/bash

## ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****
## *    dropbox_download.sh 
## *    Created by: Hugo Gaibor
## *    Date: 2026-08-05
## *    License: GNU/GPL3+
## *
## *    Usage:
## *      ./dropbox_download.sh --url="<URL>" [--filename=<FILENAME>] [--detach]
## *       
## *      (run `chmod +x dropbox_download.sh` previously) 
## *      ./dropbox_download.sh --url="<URL>" [--filename=<FILENAME>] [--detach]
## *       
## *      IMPORTANT: In order for the script to work, the file's shared permissions need
## *                 to allow the file to be downloaded publicly with no login required.
## *       
## *                 To prevent URL characters to be trimmed by bash, wrap the URL or FileId in quotes.
## *       
## *    Parameters: 
## *      - url:       Full Dropbox share link (script will auto-convert it to a direct link).
## *      - filename:  (Optional) name of the file and extension to store the file locally.
## *                   If the file is saved as 'unspecified' or some with an odd name,
## *                   use this parameter explicitly.
## *      - detach:    (Optional) launches the download in a background tmux session to allow
## *                   SSH client to be closed without interrupting the download.
## *      
## ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****

# Initialize variables
URL=""
FILENAME=""
DETACH=false

# Parse named parameters
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --url) URL="$2"; shift 2 ;;
        --url=*) URL="${1#*=}"; shift 1 ;;
        --filename) FILENAME="$2"; shift 2 ;;
        --filename=*) FILENAME="${1#*=}"; shift 1 ;;
        --detach) DETACH=true; shift 1 ;;
        *)
            echo "Error: Unknown parameter passed: $1"
            echo "Usage: $0 --url=\"<URL>\" [--filename=<FILENAME>] [--detach]"
            return 1 2>/dev/null || exit 1
            ;;
    esac
done

# Validate that the URL is provided
if [[ -z "$URL" ]]; then
    echo "Error: --url is required."
    echo "Usage: $0 --url=\"<URL>\" [--filename=<FILENAME>] [--detach]"
    return 1 2>/dev/null || exit 1
fi

# If detach is requested, verify tmux is installed
if [[ "$DETACH" == true ]] && ! command -v tmux &> /dev/null; then
    echo "Error: 'tmux' is not installed but --detach was requested."
    return 1 2>/dev/null || exit 1
fi

# Generate the runner script for handling background/foreground execution
RUNNER_SCRIPT=$(mktemp)

cat << 'EOF' > "$RUNNER_SCRIPT"
#!/bin/bash
URL="$1"
FILENAME="$2"
DETACH_MODE="$3"

echo "Converting Dropbox link to direct download stream..."

# Convert the standard share link to a direct download link
if [[ "$URL" == *"dl=0"* ]]; then
    DIRECT_URL="${URL//dl=0/dl=1}"
elif [[ "$URL" != *"dl=1"* ]]; then
    if [[ "$URL" == *"?"* ]]; then
        DIRECT_URL="${URL}&dl=1"
    else
        DIRECT_URL="${URL}?dl=1"
    fi
else
    DIRECT_URL="$URL"
fi

echo "Starting download..."

# Execute the final download
# We use -L because Dropbox uses an internal redirect to the actual storage server
if [[ -n "$FILENAME" ]]; then
    curl -L -o "$FILENAME" "$DIRECT_URL"
    echo ""
    echo "[OK] Download completed successfully!"
    echo "Saved as: $FILENAME"
else
    # Use -J and -O to let curl pull the original filename from Dropbox's headers
    curl -L -J -O "$DIRECT_URL"
    echo ""
    echo "[OK] Download completed successfully! (Check current directory for the file)"
fi

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
    SESSION_NAME="dropbox_${RANDOM:0:5}"
    echo "Starting background download in tmux session: $SESSION_NAME"
    
    tmux new-session -d -s "$SESSION_NAME" "bash '$RUNNER_SCRIPT' '$URL' '$FILENAME' 'true'"
    
    echo "Success! You can safely exit SSH."
    echo "To check progress later, run: tmux attach -t $SESSION_NAME"
else
    # Run normally in the foreground
    bash "$RUNNER_SCRIPT" "$URL" "$FILENAME" "false"
fi