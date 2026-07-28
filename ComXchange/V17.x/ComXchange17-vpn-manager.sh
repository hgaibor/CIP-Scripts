#!/bin/bash

## ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****
## *    ComXchange17-vpn-manager.sh
## *    Created by: Hugo Gaibor
## *    Date: 2026-06-24
## *    License: GNU/GPL3+
## *
## *    Latest version: 
## *        
## *        
## *    Usage:
## *       ComXchange17-vpn-manager.sh [OPTION] [PARAMETER]
## *    Options:
## *      -s, --server           Generate a new OpenVPN server certificate"
## *      -c, --client [NAME]    Generate a new OpenVPN client file (e.g., -c ext100)"
## *      -e, --edgerouter       Generate VPN certs for edgerouter based connections (client, edgerouter and support VPN)
## *      -h, --help             Display this help message"
## *    Run the script without any options to launch the interactive menu."
## *        
## ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****

# local BUILD_DIR
BUILD_DIR=$(mktemp -d)
OVPN_DIR="/etc/openvpn/server"
ERROR_COUNT=0

mkdir -p "$BUILD_DIR"
echo "Starting OpenVPN cert generation in temporary directory: $BUILD_DIR"
cd "$BUILD_DIR" || { log "Failed to cd to temp directory"; return 1; }



createOpenVPNServerCerts() {
    ERROR_COUNT=0
    if [ ! -d "$BUILD_DIR" ]; then
        displayMsg "Error: "$BUILD_DIR" does not exist. Please re-run the script."
        ((ERROR_COUNT++)) 
        return 1 2>/dev/null || exit 1
    else
        echo "Success: Found /usr/share/easy-rsa/. Proceeding..."

        initializeEasyRsaPki

        ./easyrsa --batch build-ca nopass
        ./easyrsa gen-dh
        openvpn --genkey secret ta.key
        ./easyrsa --batch build-server-full server nopass

        mkdir -p "$OVPN_DIR"
     
        cp "pki/ca.crt" "$OVPN_DIR/"
        cp "pki/private/ca.key" "$OVPN_DIR/" # Addressing missing CA.key copy
        cp "pki/issued/server.crt" "$OVPN_DIR/"
        cp "pki/private/server.key" "$OVPN_DIR/"
        cp "pki/dh.pem" "$OVPN_DIR/dh2048.pem"
        cp "pki/serial" "$OVPN_DIR/" # OpenSSL will complain if these are not present when creating new cert with this CA
        cp "pki/index.txt" "$OVPN_DIR/" # OpenSSL will complain if these are not present when creating new cert with this CA
        cp "ta.key" "$OVPN_DIR/"
     
        chmod 600 "$OVPN_DIR/server.key"

    fi
}

initializeEasyRsaPki(){
    # Check if easy-rsa has been initialized
    if [ -d "$BUILD_DIR/pki" ]; then
        echo "NOTICE: Easy-rsa is already intialized, no files have been copied"
        return 1
    fi

    if [ ! -d "$BUILD_DIR" ]; then
        displayMsg "Error: "$BUILD_DIR" does not exist. Please re-run the script."
        ((ERROR_COUNT++)) 
        return 1 2>/dev/null || exit 1
    else
        cd "$BUILD_DIR" || { log "Failed to cd to temp directory"; ((ERROR_COUNT++)); return 1; }
    fi

    if [ ! -d "/usr/share/easy-rsa" ]; then
        displayMsg "Error: /usr/share/easy-rsa/ does not exist. Please install easy-rsa first."
        ((ERROR_COUNT++))
        return 1 2>/dev/null || exit 1
    else
        echo "Success: Found /usr/share/easy-rsa/. Proceeding..."
        
        cp -r /usr/share/easy-rsa/* .

        # Export won't work on this version of easy-rsa. Will create vars file with this information
        # export EASYRSA_REQ_COUNTRY="US"
        # export EASYRSA_REQ_PROVINCE="WI"
        # export EASYRSA_REQ_OU="ComXchange17"
        # export EASYRSA_CERT_EXPIRE="3650"
        # export EASYRSA_REQ_EMAIL="info@14ip.com"
        # export EASYRSA_REQ_ORG="14IP"

        # Define the target vars file
        VARS_FILE="$BUILD_DIR/vars"

        echo "--- Creating Easy-RSA vars file to store ComX VPN info ---"

        # 1. Use a single '>' to create/overwrite the file with the first line
        echo "# Custom Easy-RSA Variables" > "$VARS_FILE"

        # 2. Use double '>>' to append the remaining variables to the file
        echo "set_var EASYRSA_DN  \"org\"" >> "$VARS_FILE"
        echo "set_var EASYRSA_REQ_COUNTRY  \"US\"" >> "$VARS_FILE"
        echo "set_var EASYRSA_REQ_PROVINCE \"WI\"" >> "$VARS_FILE"
        echo "set_var EASYRSA_REQ_CITY \"Appleton\"" >> "$VARS_FILE"
        echo "set_var EASYRSA_REQ_OU       \"ComXchange17\"" >> "$VARS_FILE"
        echo "set_var EASYRSA_CERT_EXPIRE  3650" >> "$VARS_FILE"
        echo "set_var EASYRSA_REQ_EMAIL    \"info@14ip.com\"" >> "$VARS_FILE"
        echo "set_var EASYRSA_REQ_ORG      \"14IP\"" >> "$VARS_FILE"

        # Verify the file was created successfully
        if [ -f "$VARS_FILE" ]; then
            echo "Success: '$VARS_FILE' has been created."
        else
            displayMsg "Error: Failed to create vars file at '$VARS_FILE'."
            ((ERROR_COUNT++)) 
            return 1 2>/dev/null || exit 1
        fi

        ./easyrsa init-pki
        
        # Define the target index.attr file
        INDEX_ATTR_FILE="$BUILD_DIR/pki/index.txt.attr"

        echo "unique_subject = no" > "$INDEX_ATTR_FILE"

        # Verify the file was created successfully
        if [ -f "$INDEX_ATTR_FILE" ]; then
            echo "Success: '$INDEX_ATTR_FILE' has been created."
        else
            displayMsg "Error: Failed to create index.txt.attr file at '$INDEX_ATTR_FILE'."
            ((ERROR_COUNT++)) 
            return 1 2>/dev/null || exit 1
        fi

    fi

    
}

getExistingVPNRequiredFiles() {

    local REQUIRED_FILES=(
        "ca.crt"
        "ca.key"
        "server.crt"
        "server.key"
        "dh2048.pem"
        "ta.key"
        "serial" # Adding serial file to fix error Missing expected CA file: serial (perhaps you need to run build-ca?)
        "index.txt" # Adding index.txt to fix error Missing expected CA file: index.txt (perhaps you need to run build-ca?)
        # "index.txt.attr" # This file is also required, but will generate it on the fly via code
    )

    # 2. Check if the directory itself exists first
    if [ ! -d "$OVPN_DIR" ]; then
        displayMsg "Error: Directory '$OVPN_DIR' does not exist."
        ((ERROR_COUNT++))
        return 1 2>/dev/null || exit 1
    fi

    # 3. Loop through the array and check each file
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "$OVPN_DIR/$file" ]; then
            displayMsg "Error: Required file '$file' is missing from '$OVPN_DIR'. Run createOpenVPNServerCerts() first"
            ((ERROR_COUNT++))
            # Exit using the SSH-safe exit trick
            return 1 2>/dev/null || exit 1
        fi
    done

    # Check if easy-rsa has been initialized
    if [ ! -d "$BUILD_DIR/pki" ]; then
        echo "NOTICE: Easy-rsa is not intialized, initializing"
        initializeEasyRsaPki
    fi

    if ((ERROR_COUNT > 0)); then
        displayMsg "Errors were found, can not proceed"
        return 1 2>/dev/null || exit 1
    else
        echo "Success: VPN files are present in '$OVPN_DIR'. Copying files to $BUILD_DIR"

        cp -f "$OVPN_DIR/ca.crt" "$BUILD_DIR/pki/"
        cp -f "$OVPN_DIR/ca.key" "$BUILD_DIR/pki/private/"

        # Commented files are not needed for new VPN certs
        # cp -f "$OVPN_DIR/server.crt" "$BUILD_DIR/pki/"
        # cp -f "$OVPN_DIR/server.key" "$BUILD_DIR/pki/private/"
        # cp -f "$OVPN_DIR/dh.pemdh2048.pem" "$BUILD_DIR/pki/"

        cp -f "$OVPN_DIR/ta.key" "$BUILD_DIR/"
        cp -f "$OVPN_DIR/serial" "$BUILD_DIR/pki/"
        cp -f "$OVPN_DIR/index.txt" "$BUILD_DIR/pki/"
    
        echo "Copied VPN files complete $BUILD_DIR"
    fi
}

createOpenVPNClient() {
    local CLIENT_NAME="$1"
    local CLIENT_DIR="/root/OVPN/$CLIENT_NAME"
    local CLIENT_CONFIG="$CLIENT_DIR/client.ovpn"

    cd "$BUILD_DIR" || { log "Failed to cd to temp directory"; return 1; }

    # Check if easy-rsa has been initialized
    if [ ! -d "$BUILD_DIR/pki" ]; then
        echo "NOTICE: Easy-rsa is not intialized, initializing"
        initializeEasyRsaPki
    fi


    mkdir -p "$CLIENT_DIR"
    rm -f "$CLIENT_CONFIG"

    # Creating directories since we'll inject the ca.crt and ca.key files 
    # OpenSSL will complain and error if any of these is missing when reconstructing pki with existing CA files
    mkdir -p "pki/certs_by_serial"
    mkdir -p "pki/issued"
    mkdir -p "pki/private"
    mkdir -p "pki/renewed"
    mkdir -p "pki/reqs"
    mkdir -p "pki/revoked"

    getExistingVPNRequiredFiles

    if ((ERROR_COUNT > 0)); then
        displayMsg "Errors were found, can not proceed"
        return 1 2>/dev/null || exit 1
    else
        cd "$BUILD_DIR" || { log "Failed to cd to temp directory"; return 1; }

        ./easyrsa --batch build-client-full $CLIENT_NAME nopass

        cp -f "pki/ca.crt" "$CLIENT_DIR/"
        cp -f "pki/issued/$CLIENT_NAME.crt" "$CLIENT_DIR/"
        cp -f "pki/private/$CLIENT_NAME.key" "$CLIENT_DIR/"
        cp -f "ta.key" "$CLIENT_DIR/"

        # Copying updated index.txt and serial files for future VPN generation
        cp -f "$BUILD_DIR/pki/serial" "$OVPN_DIR/"
        cp -f "$BUILD_DIR/pki/index.txt" "$OVPN_DIR/"


        {
            echo "tls-client"
            echo "dev tap"
            echo "proto udp"
            echo "remote 127.0.0.1 1194"
            echo "resolv-retry infinite"
            echo "nobind"
            echo "persist-key"
            echo "persist-tun"
            echo "mtu-test"
            echo "verb 4"
            echo "mute 20"
            echo "pull"
            echo "ca ca.crt"
            echo "cert $CLIENT_NAME.crt"
            echo "key $CLIENT_NAME.key"
            echo "tls-crypt ta.key"
            echo "tun-mtu 1500"
            echo "tun-mtu-extra 32"
            echo "mssfix 1450"
            echo "reneg-sec 0"
            # Below line is not needed for this version of openVPN with TLS enabled
            # echo "tls-cipher DEFAULT:@SECLEVEL=0"
        } > "$CLIENT_CONFIG"
    fi
}




# createOpenVPNServerCerts
# createOpenVPNClient
# createOpenVPNPhoneClient
# createOpenVPNSupportClient


# systemctl enable openvpn-server@server.service && systemctl start openvpn-server@server.service && systemctl restart openvpn-server@server.service  && systemctl status openvpn-server@server.service -l

runVPNCleanUps() {
    cd "/root"
    rm -rf "$BUILD_DIR" 2>/dev/null
}

displayMsg() {
    # Assign the first positional parameter ($1) to a local variable for readability
    local error_message_text="$1"

    # 2. Validate that a parameter was actually provided
    if [ -z "$error_message_text" ]; then
        echo "Error: Undefined error" >&2
        return 1 2>/dev/null || exit 1
    fi

    # 3. Process the text
    echo "$error_message_text" >&2
    
    # Pause and wait for a keypress
    read -n 1 -s -r -p "Press any key to continue..."
    echo "" # Prints a clean newline after the user presses a key
    
    return 1 2>/dev/null || exit 1
    # exit 1
}

interactive_menu(){
    # Change the default prompt text (PS3 is specifically used by the 'select' command)
    PS3="Please select an action (1-3, or 'q' to quit): "

    # Define your options in an array
    options=(
        "Generate New Server VPN certs"
        "Add New Client"
        "Exit"
    )

    # options=("Generate New Server" "Add New Client" "Exit")

    echo "=== OpenVPN Management Menu ==="

    # The select loop automatically lists the options with numbers
    select opt in "${options[@]}"; do

        # 1. INTERCEPT HOTKEYS FIRST
        # Check the raw input ($REPLY) before checking the menu options ($opt)
        if [[ "$REPLY" == "q" || "$REPLY" == "Q" ]]; then
            echo "Exiting script."
            runVPNCleanUps
            return 0 2>/dev/null || exit 0
        fi

        case $opt in
            "Generate New Server VPN certs")
                echo "Starting server generation..."
                createOpenVPNServerCerts
                # break
                ;;
            "Add New Client")
                read -p "Enter the new client name: " client_name
                echo "Generating keys for: $client_name"
                createOpenVPNClient $client_name
                # Call your client function here, passing $client_name
                # break
                ;;
            "Exit")
                echo "Exiting script."
                runVPNCleanUps
                return 0 2>/dev/null || exit 0
                ;;
            *) 
                # Catch-all for invalid numbers
                echo "Invalid option: $REPLY. Please try again."
                ;;
        esac

        REPLY=
    done    
}


show_help() {
    echo "Usage: $0 [OPTION] [ARGUMENT]"
    echo ""
    echo "Options:"
    echo "  -s, --server           Generate a new OpenVPN server certificate"
    echo "  -c, --client [NAME]    Generate a new OpenVPN client file (e.g., -c ext100)"
    echo "  -e, --edgerouter       Generate VPN certs for edgerouter based connections (client, edgerouter and support VPN)"
    echo "  -h, --help             Display this help message"
    echo ""
    echo "Run the script without any options to launch the interactive menu."
}


# ==========================================
# 3. MAIN SCRIPT LOGIC (THE PARAMETER CHECK)
# ==========================================

# Check the first parameter passed to the script ($1)
case "$1" in
    -s|--server)
        createOpenVPNServerCerts
        echo "Running tmp files cleanup"
        runVPNCleanUps
        echo "Done!"
        ;;
    -c|--client)
        # Pass the second parameter ($2) directly to the function as the client name
        createOpenVPNClient "$2"
        echo "Running tmp files cleanup"
        runVPNCleanUps
        echo "Done!"
        cd "/root/OVPN/"
        ;;

    -e|--edgerouter)
        # This will create three files, for client, edgerouter and support, in a single step 
        # Pass the second parameter ($2) directly to the function as the client name
        displayMsg "This will create three files, for client, edgerouter and support"
        createOpenVPNClient "client"
        createOpenVPNClient "edgerouter"
        createOpenVPNClient "support"
        echo "Running tmp files cleanup"
        runVPNCleanUps
        echo "Done!"
        cd "/root/OVPN/"
        ;;

    -h|--help)
        show_help
        ;;
    "")
        # If $1 is empty (no parameters were provided), launch the menu
        interactive_menu
        ;;
    *)
        # If they typed a parameter that doesn't exist
        echo "Error: Unknown parameter '$1'" >&2
        echo "Use -h or --help for usage information." >&2
        return 1 2>/dev/null || exit 1
        ;;
esac