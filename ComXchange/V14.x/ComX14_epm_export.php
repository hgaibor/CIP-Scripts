<?php
// ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****
// *    ComX14_epm_export.php
// *    Created by: Hugo Gaibor
// *    Date: 2026-07-28
// *    License: GNU/GPL3+
// *
// *    Latest version: 
// *        
// *        
// *    Usage:
// *       php ComX14_epm_export.php
// *        
// *       This script will export ComXchange extensions taken from third party endpoint manager
// *       in ComXchange 14, it won't be compatible with OSS endpoint manager or other versions. 
// *        
// *        
// ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** ***** *****

// Bootstrap FreePBX to gain access to the database configuration and PDO object
if (!@include_once(getenv('FREEPBX_CONF') ? getenv('FREEPBX_CONF') : '/etc/freepbx.conf')) {
    die("Could not find FreePBX configuration file. Are you running this on the PBX?\n");
}

// Access the FreePBX Database object (PDO)
$db = \FreePBX::Database();

/* 
 * This query joins the Endpointman tables with the FreePBX core tables.
 * It checks both the 'sip' table (chan_sip) and 'ps_auths' (pjsip) for the password.
 */
$sql = "
    SELECT 
        m.mac AS mac_address,
        l.ext AS extension,
        l.line AS line_key,
        COALESCE(s.data, p.data, 'No Password Found') AS secret
    FROM 
        comxendpointman_mac_list m
    JOIN 
        comxendpointman_line_list l ON m.id = l.mac_id
    LEFT JOIN 
        sip s ON l.ext = s.id AND s.keyword = 'secret'
    LEFT JOIN 
        pjsip p ON l.ext = p.id
    ORDER BY 
        l.ext ASC
";

try {
    $stmt = $db->prepare($sql);
    $stmt->execute();
    $results = $stmt->fetchAll(\PDO::FETCH_ASSOC);

    // Output formatting
    $format = "%-18s | %-10s | %-8s | %-20s\n";
    echo sprintf($format, "MAC Address", "Extension", "Line Key", "Secret");
    echo str_repeat("-", 62) . "\n";

    foreach ($results as $row) {
        echo sprintf(
            $format, 
            $row['mac_address'], 
            $row['extension'], 
            $row['line_key'], 
            $row['secret']
        );
    }

} catch (\Exception $e) {
    die("Database query failed: " . $e->getMessage() . "\n");
}
?>