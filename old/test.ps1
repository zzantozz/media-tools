# This is cobbled together from a little bit of googling and based on my auto-mkv-disc.sh script.
# If there seems like an excess of assignments and this looks a little like bash, that's why.

$ErrorActionPreference = "Stop"

$fDrive = Get-WMIObject Win32_Volume | ? {$_.DriveLetter -eq 'f:'}
$label = $fDrive.label.Trim()

Write-Host "Disk label is '$label'"

$MAKEMKV_BINARY="d:\apps\MakeMkv\makemkvcon"
$BASE_OUTPUT_DIR="x:\ripping\__1-auto-ripped"
$DISC="$label"
$TARGET_DIR="$DISC"
$FINAL_TARGET_DIR="$BASE_OUTPUT_DIR\$TARGET_DIR"

# look ma! no Write-Host!
"Binary: $MAKEMKV_BINARY"
"Output dir: $FINAL_TARGET_DIR"

mkdir -f "$BASE_OUTPUT_DIR" | Out-Null
mkdir "$FINAL_TARGET_DIR" | Out-Null

if ( $? -eq $False ) {
    exit 1
}

Write-Host "Starting rip to $FINAL_TARGET_DIR"

echo $null > "$FINAL_TARGET_DIR/.lock"
echo $null > "$FINAL_TARGET_DIR/.ripping"
echo "**************************************"
& $MAKEMKV_BINARY mkv disc:0 all $FINAL_TARGET_DIR
echo "**************************************"
rm "$FINAL_TARGET_DIR/.ripping"
rm "$FINAL_TARGET_DIR/.lock"
echo $null > "$FINAL_TARGET_DIR/.ripping-finished"
