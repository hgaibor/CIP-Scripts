<?php
// ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****
// *    CIP_cloud_migration.php
// *    Created by: Hugo Gaibor
// *    Date: 2026-07-28
// *    License: GNU/GPL3+
// *
// *    Latest version: 
// *        
// *        
// *    Usage:
// *       php CIP_cloud_migration.php > CSV_FILE.csv
// *       php CIP_cloud_migration.php # For on-screen output
// *        
// *       This script will export FreePBX-based systems user information info a format compatible
// *       to be imported in ClearlyCloud, tested in FreePBX 14 + PHP 5.4 system
// *       Should work in older systems as it gets the information directly from database structures 
// *        
// *        
// ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****

if (php_sapi_name() !== 'cli') {
    die("Error: This script must be run from the command line.\n");
}

if (!file_exists('/etc/freepbx.conf')) {
    die("Error: /etc/freepbx.conf not found.\n");
}
require_once '/etc/freepbx.conf';

global $db; 

if (!$db) {
    die("Error: Could not connect to the FreePBX database.\n");
}

function queryDb($db, $sql) {
    try {
        $stmt = $db->prepare($sql);
        $stmt->execute();
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (Exception $e) {
        return array();
    }
}

// PHP 8+ Safe Trim Function (Guarantees no nulls reach native trim)
function safe_trim($value) {
    return trim((string)$value);
}

// Random Password Generator (Alphanumeric)
function generateRandomPassword($length = 16) {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    $password = '';
    $max = strlen($chars) - 1;
    for ($i = 0; $i < $length; $i++) {
        $password .= $chars[mt_rand(0, $max)];
    }
    return $password;
}

// Random 6-digit PIN Generator
function generateRandomPin() {
    return sprintf('%06d', mt_rand(0, 999999));
}

// 1. Define the full template with all required CSV headers and new default values
$rowTemplate = array(
    'ID' => '',
    'First Name' => '',
    'Last Name' => '',
    'Username' => '',
    'Email' => '',
    'Time Zone' => '',
    'Web Password' => '',
    'SIP Password' => '',
    'Voicemail Enabled' => '',
    'Voicemail Pin' => '',
    'Voicemail Play CID' => '',
    'Voicemail Play Envelope' => '',
    'Voicemail Transcription' => '',
    'Voicemail Notification' => '',
    'Voicemail Notification Use Login' => '',
    'Extension' => '',
    'Department' => '',
    'Language' => 'en-US',
    'Phone Model ID' => '',
    'Provisioning Template ID' => '',
    'Mac Address' => '',
    'User Profile ID' => '',
    'Forward Number' => '',
    'Followme Number' => '',
    'DND On' => '0',
    'Callwaiting on' => '1',
    'Feature Set' => '',
    'IP address' => '',
    'Internal Caller ID Name' => '',
    'Internal Caller ID Number' => '',
    'External Caller ID Name' => '',
    'External Caller ID Number' => '',
    'SMS DID' => '',
    'Custom Destination On Unavailable' => '',
    'Custom Destination On Busy' => '',
    'Voicemail Option 0 Destination' => '',
    'Default Callback Profile' => '',
    'Default Dispatchable Location' => '',
    'Dial Timeout' => '',
    'Contact Tags' => 'default',
    'Disabled Direct Media' => '0',
    'Screen Pop Type' => 'none',
    'Screen Pop Trigger' => 'ringing',
    'Screen Pop URL' => '',
    'Followme Enabled' => '0',
    'Followme Ring Strategy' => 'ringall',
    'Followme Press 1' => '0',
    'Followme Caller ID Prefix' => '',
    'Followme Caller ID Type' => '0',
    'Followme External Caller ID' => '',
    'Followme Delay Between Devices' => '0',
    'Followme Ring Timeout' => '20',
    'Followme Mark Answered' => 'FALSE',
    'White List Extensions' => '',
    'Voicemail Limit' => '',
    'Voicemail Disable VM Rotate' => '0',
    'Voicemail Categorize' => '',
    'Voicemail Summarize' => '',
    'Voicemail Translation' => '',
    'Voicemail Translation Language' => '',
    'Voicemail to Email' => '',
    'Voicemail short notification to' => '',
    'Voicemail Delete after Notification' => '',
    'User Permission Group ID' => '',
    'User Permissions IDs' => ''
);

$data = array();

// 2. Query the Core module's 'users' table
$coreSql = "SELECT extension, name AS display_name FROM users";
$coreRecords = queryDb($db, $coreSql);

foreach ($coreRecords as $row) {
    $ext = safe_trim($row['extension']); 
    
    if ($ext !== '') {
        $data[$ext] = $rowTemplate;
        $data[$ext]['Extension'] = $ext;
        $data[$ext]['Internal Caller ID Number'] = $ext;
        $data[$ext]['Internal Caller ID Name'] = safe_trim($row['display_name']);
    }
}

// 3. Parse /etc/asterisk/voicemail.conf to extract detailed voicemail data
$vmData = array();
$vmFile = '/etc/asterisk/voicemail.conf';

if (file_exists($vmFile)) {
    $lines = file($vmFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    
    foreach ($lines as $line) {
        $line = safe_trim($line);
        if (strpos($line, ';') === 0 || strpos($line, '[') === 0) {
            continue;
        }
        
        if (strpos($line, '=') !== false) {
            list($mailbox, $config) = explode('=', $line, 2);
            $mailbox = safe_trim($mailbox);
            $configParts = explode(',', safe_trim($config));
            
            $pin = (isset($configParts[0]) && safe_trim($configParts[0]) !== '') ? safe_trim($configParts[0]) : generateRandomPin();
            $email = isset($configParts[2]) ? safe_trim($configParts[2]) : '';
            
            $saycid = '';
            $envelope = '';
            $delete = '';
            
            if (isset($configParts[4])) {
                $optionsStr = safe_trim($configParts[4]);
                $optionsArr = explode('|', $optionsStr);
                
                foreach ($optionsArr as $opt) {
                    $optParts = explode('=', $opt);
                    if (count($optParts) === 2) {
                        $key = strtolower(safe_trim($optParts[0]));
                        $val = strtolower(safe_trim($optParts[1]));
                        
                        if ($key === 'saycid') $saycid = $val;
                        if ($key === 'envelope') $envelope = $val;
                        if ($key === 'delete') $delete = $val;
                    }
                }
            }
            
            $vmData[$mailbox] = array(
                'Voicemail Pin' => $pin,
                'Email' => $email,
                'Voicemail Play CID' => $saycid,
                'Voicemail Play Envelope' => $envelope,
                'Voicemail Delete after Notification' => $delete
            );
        }
    }
}

// Map parsed voicemail data to the main array
foreach ($vmData as $ext => $vm) {
    if (array_key_exists($ext, $data)) {
        $data[$ext]['Voicemail Enabled'] = 'TRUE';
        $data[$ext]['Voicemail Transcription'] = 'yes';
        $data[$ext]['Voicemail Notification'] = 'yes';
        $data[$ext]['Voicemail Notification Use Login'] = 'yes';
        $data[$ext]['Voicemail Categorize'] = 'yes';
        $data[$ext]['Voicemail Summarize'] = 'yes';
        $data[$ext]['Voicemail Translation'] = 'no';
        
        $data[$ext]['Voicemail Pin'] = $vm['Voicemail Pin'];
        
        if ($vm['Voicemail Play CID'] !== '') {
            $data[$ext]['Voicemail Play CID'] = $vm['Voicemail Play CID'];
        }
        if ($vm['Voicemail Play Envelope'] !== '') {
            $data[$ext]['Voicemail Play Envelope'] = $vm['Voicemail Play Envelope'];
        }
        if ($vm['Voicemail Delete after Notification'] !== '') {
            $data[$ext]['Voicemail Delete after Notification'] = $vm['Voicemail Delete after Notification'];
        }
        
        $data[$ext]['Email'] = $vm['Email'];
        $data[$ext]['Voicemail to Email'] = $vm['Email'];
    }
}

// 4. Query the User Management 'userman_users' table
$userSql = "SELECT default_extension, fname, lname, email FROM userman_users";
$userRecords = queryDb($db, $userSql);

foreach ($userRecords as $row) {
    $ext = safe_trim($row['default_extension']);
    $umEmail = safe_trim($row['email']);
    
    // Only process if the extension is NOT empty and matches a known core extension
    if ($ext !== '' && array_key_exists($ext, $data)) {
        $data[$ext]['First Name'] = safe_trim($row['fname']);
        $data[$ext]['Last Name'] = safe_trim($row['lname']);
        
        if ($data[$ext]['Email'] === '' && $umEmail !== '') {
            $data[$ext]['Email'] = $umEmail;
        }
    }
    // Standalone users (no linked extension) are ignored.
}

// 5. Apply Logic (Names, Usernames, Passwords, Validations)
foreach ($data as $key => $row) {
    
    // FALLBACK: If First and Last name are empty, try extracting them from the Display Name
    if ($row['First Name'] === '' && $row['Last Name'] === '' && $row['Internal Caller ID Name'] !== '') {
        if ($row['Internal Caller ID Name'] !== $row['Extension']) {
            $nameParts = explode(' ', safe_trim($row['Internal Caller ID Name']), 2);
            $row['First Name'] = safe_trim($nameParts[0]);
            $row['Last Name'] = isset($nameParts[1]) ? safe_trim($nameParts[1]) : '';
            
            $data[$key]['First Name'] = $row['First Name'];
            $data[$key]['Last Name'] = $row['Last Name'];
        }
    }

    // VALIDATION: First Name cannot be empty
    if ($data[$key]['First Name'] === '') {
        $data[$key]['First Name'] = $row['Extension'];
        $row['First Name'] = $row['Extension']; 
    }
    
    // VALIDATION: Last Name cannot be empty
    if ($data[$key]['Last Name'] === '') {
        $data[$key]['Last Name'] = '.';
        $row['Last Name'] = '.'; 
    }

    // VALIDATION: Hardened Email Check
    $currentEmail = safe_trim($row['Email']);
    $isValidEmail = ($currentEmail !== '' && filter_var($currentEmail, FILTER_VALIDATE_EMAIL) !== false);

    // DYNAMIC USERNAME LOGIC
    if ($isValidEmail) {
        $data[$key]['Username'] = $currentEmail;
    } else {
        // Generate Username using Name and Extension if email is invalid
        $fLetter = ($row['First Name'] !== '') ? substr($row['First Name'], 0, 1) : '';
        $lName = ($row['Last Name'] !== '') ? $row['Last Name'] : '';
        $extVal = ($row['Extension'] !== 'No Extension') ? $row['Extension'] : '';
        
        $generatedUser = $fLetter . $lName . $extVal;
        $generatedUser = strtolower(str_replace(' ', '', $generatedUser));
        
        if ($generatedUser === '') {
            $generatedUser = $extVal;
        }

        $data[$key]['Username'] = $generatedUser;
    }
    
    // VALIDATION: Assign default email if the existing one is invalid or missing
    if (!$isValidEmail) {
        $data[$key]['Email'] = 'noemail@noemail.com';
        
        // Also update the Voicemail to Email if it was enabled
        if ($data[$key]['Voicemail Enabled'] === 'TRUE') {
            $data[$key]['Voicemail to Email'] = 'noemail@noemail.com';
        }
    }
    
    // RANDOM PASSWORD GENERATION
    $data[$key]['Web Password'] = generateRandomPassword(16);
    $data[$key]['SIP Password'] = generateRandomPassword(16);
}

// 6. Write output to CSV
$output = fopen('php://output', 'w');

if (!empty($data)) {
    reset($data);
    $firstKey = key($data);
    
    // Write Headers
    fputcsv($output, array_keys($data[$firstKey]));
    
    // Write Rows
    foreach ($data as $row) {
        fputcsv($output, array_values($row));
    }
} else {
    echo "No extension or user records found in the database.\n";
}

fclose($output);