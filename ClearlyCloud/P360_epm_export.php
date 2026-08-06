<?php
## ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****
## *    P360_epm_export.php
## *    Created by: Hugo Gaibor
## *    Date: 2026-08-05
## *    License: GNU/GPL3+
## *
## *    Usage:
## *       php P360_epm_export.php
## *       php P360_epm_export.php --system-type=p360 > output.csv
## *       php P360_epm_export.php --system-type=fpbx > output.csv
## *       php P360_epm_export.php > output.csv
## *       php P360_epm_export.php --template_id=12 --template_model_id=45 > output.csv
## *       php P360_epm_export.php --template-id 12 --model-id 45 --hide-phone-details > output.csv
## *        
## *       This script will export extensions taken from endpoint manager (commercial endpoint version)
## *       mapping into a CSV format compatible with Clearly Device Manager (CDM). 
## *        
## *    Parameters: 
## *      - --template-id         : (Optional) CDM template id, create it at 
## *                                https://devices.clearlyip.com/dashboard/cdm/template
## *             
## *      - --template-model-id   : (Optional) CDM template model id, once template has been created, 
## *                                get the ID of the model and use it here.
## *                                Also the flag '--model-id' can be used instead of '--template-model-id'
## *      
## *      - --hide-phone-details  : (Optional) This will not include the phone model and brand into the CSV 
## *      
## *      - --system-type         : (Optional) [p360|pulsar360|fpbx|freepbx|pbxact] (default: fpbx) 
## *      
## *      NOTE: Script may not fully export Sangoma DB20 Dect based phone, since MAC will become empty
## *      
## ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****

if (php_sapi_name() !== 'cli') {
    die("Error: This script must be run from the command line.\n");
}

## 1. Accept and validate the parameters using getopt
$longopts = array(
    "template_id:",
    "template-id:",
    "template_model_id:",
    "template-model-id:",
    "model_id:",
    "model-id:",
    "hide-phone-details",
    "system-type:",
    "system_type:"
);
$options = getopt("", $longopts);

## Determine template_id with fallback placeholder
$template_id = 'ENTER_CDM_TEMPLATE_ID';
if (isset($options['template_id'])) {
    $template_id = $options['template_id'];
} elseif (isset($options['template-id'])) {
    $template_id = $options['template-id'];
}

## Determine template_model_id with fallback placeholder
$template_model_id = 'ENTER_CDM_MODEL_ID';
if (isset($options['template_model_id'])) {
    $template_model_id = $options['template_model_id'];
} elseif (isset($options['template-model-id'])) {
    $template_model_id = $options['template-model-id'];
} elseif (isset($options['model_id'])) {
    $template_model_id = $options['model_id'];
} elseif (isset($options['model-id'])) {
    $template_model_id = $options['model-id'];
}

## Check if we should hide phone details
$hide_phone_details = isset($options['hide-phone-details']);

## Determine system type (default to fpbx)
$system_type = 'fpbx';
if (isset($options['system-type'])) {
    $system_type = strtolower(trim($options['system-type']));
} elseif (isset($options['system_type'])) {
    $system_type = strtolower(trim($options['system_type']));
}

## For now, all defined system types share the same table naming convention
$tbl_endpoint_extensions = 'endpoint_extensions';

## 2. Bootstrap FreePBX database connection
if (!file_exists('/etc/freepbx.conf')) {
    die("Error: /etc/freepbx.conf not found.\n");
}
require_once '/etc/freepbx.conf';

global $db; 

if (!$db) {
    die("Error: Could not connect to the database.\n");
}

function queryDb($db, $sql) {
    try {
        $stmt = $db->prepare($sql);
        $stmt->execute();
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (Exception $e) {
        ## Outputting error directly to stderr so it doesn't corrupt standard CSV output
        error_log("DB Query Error: " . $e->getMessage()); 
        return array();
    }
}

## 3. Pre-fetch SIP Ports from the kvstore_Sipsettings table
$pjsip_port_query = queryDb($db, "SELECT val FROM kvstore_Sipsettings WHERE `key` = 'udpport-0.0.0.0' LIMIT 1");
$pjsip_port = !empty($pjsip_port_query) ? $pjsip_port_query[0]['val'] : '5060'; ## fallback port

$chansip_port_query = queryDb($db, "SELECT val FROM kvstore_Sipsettings WHERE `key` = 'bindport' LIMIT 1");
$chansip_port = !empty($chansip_port_query) ? $chansip_port_query[0]['val'] : '5160'; ## fallback port

## 4. Construct Query for MAC, Extension, SIP Driver, and Phone Details
## We use SUBSTRING_INDEX on e.ext to remove "-1" extensions so the JOIN with the sip table matches correctly
$sql = "
    SELECT 
        e.mac, 
        e.ext AS raw_extension, 
        e.accessory AS extension_ipei, 
        s.data AS sipdriver,
        e.model AS phone_model,
        e.brand AS phone_brand
    FROM {$tbl_endpoint_extensions} e
    LEFT JOIN sip s ON (SUBSTRING_INDEX(e.ext, '-', 1) = s.id AND s.keyword = 'sipdriver')
";

$records = queryDb($db, $sql);

## 5. Define CSV Headers
$headers = array(
    'mac',
    'template_id',
    'template_model_id',
    'extension_number',
    'registration',
    'device_number',
    'sip_port',
    'outbound_proxy_port',
    'transport_type',
    'media_type',
    'is_remote',
    'ipei',
    'add_to_redirect'
);

## Prepend the brand and model columns if the flag is not set
if (!$hide_phone_details) {
    array_unshift($headers, 'phone_brand', 'phone_model');
}

## 6. Generate CSV to output buffer
$output = fopen('php://output', 'w');
fputcsv($output, $headers);

if (!empty($records)) {
    ## Array to keep track of how many times a MAC address appears
    $mac_tracking = array();

    foreach ($records as $row) {
        $sip_port = '';
        $driver = isset($row['sipdriver']) ? trim($row['sipdriver']) : '';
        
        ## Validate extension driver and map corresponding port
        if ($driver === 'chan_pjsip') {
            $sip_port = $pjsip_port;
        } elseif ($driver === 'chan_sip') {
            $sip_port = $chansip_port;
        }

        ## Clean the extension number by stripping anything after a dash
        $ext_parts = explode('-', $row['raw_extension']);
        $clean_extension = trim($ext_parts[0]);

        ## Increment registration count for duplicate MAC addresses
        $current_mac = trim($row['mac']);
        if (!isset($mac_tracking[$current_mac])) {
            $mac_tracking[$current_mac] = 1;
        } else {
            $mac_tracking[$current_mac]++;
        }
        $registration_val = (string)$mac_tracking[$current_mac];
        
        ## Build the core row with specified default values
        $csvRow = array(
            $row['mac'],             
            $template_id,            ## From script parameter or placeholder
            $template_model_id,      ## From script parameter or placeholder
            $clean_extension,        ## Cleaned endpoint_extensions.ext
            $registration_val,       ## Dynamically incremented registration counter
            '1',                     ## device_number
            $sip_port,               ## validated kvstore_Sipsettings port
            '',                      ## outbound_proxy_port
            'UDP',                   ## transport_type
            'RTP/NONE',              ## media_type
            'No',                    ## is_remote
            $row['extension_ipei'],  ## ipei
            'No'                     ## add_to_redirect
        );
        
        ## Prepend brand and model data if the flag is not set
        if (!$hide_phone_details) {
            array_unshift(
                $csvRow, 
                isset($row['phone_brand']) ? $row['phone_brand'] : '', 
                isset($row['phone_model']) ? $row['phone_model'] : ''
            );
        }
        
        fputcsv($output, $csvRow);
    }
}

fclose($output);