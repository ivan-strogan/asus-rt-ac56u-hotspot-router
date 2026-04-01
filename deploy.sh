#!/bin/bash
# Deploy scripts to RT-AC56U
# Run from your Mac: bash deploy.sh
# Requires SSH access to the router at 192.168.1.1

ROUTER="admin@192.168.1.1"
SCP="scp -O"  # -O forces legacy SCP protocol (router doesn't support SFTP)

echo "=== Deploying to $ROUTER ==="

# Ensure directories exist on router
ssh $ROUTER "mkdir -p /jffs/scripts /jffs/previous"

# Upload all scripts
echo "--- Uploading scripts ---"
$SCP scripts/log.sh            $ROUTER:/jffs/scripts/log.sh
$SCP scripts/init-start        $ROUTER:/jffs/scripts/init-start
$SCP scripts/firewall-start    $ROUTER:/jffs/scripts/firewall-start
$SCP scripts/services-start    $ROUTER:/jffs/scripts/services-start
$SCP scripts/wan-watchdog.sh   $ROUTER:/jffs/scripts/wan-watchdog.sh
$SCP scripts/self-update.sh    $ROUTER:/jffs/scripts/self-update.sh
$SCP scripts/dnsmasq-dhcp.conf $ROUTER:/jffs/dnsmasq-dhcp.conf
$SCP scripts/udhcpc.script     $ROUTER:/jffs/udhcpc.script

# Set execute permissions
echo "--- Setting permissions ---"
ssh $ROUTER "chmod +x /jffs/scripts/init-start \
                       /jffs/scripts/firewall-start \
                       /jffs/scripts/services-start \
                       /jffs/scripts/wan-watchdog.sh \
                       /jffs/scripts/self-update.sh \
                       /jffs/udhcpc.script"

# Activate watchdog immediately without reboot
echo "--- Activating watchdog ---"
ssh $ROUTER "cru d wan-watchdog 2>/dev/null; \
             cru a wan-watchdog '* * * * * /jffs/scripts/wan-watchdog.sh'; \
             touch /tmp/setup_done"

echo "--- Rebooting router ---"
ssh $ROUTER "reboot"

echo ""
echo "Waiting 3 minutes for router to boot..."
sleep 180

echo ""
echo "=== Post-boot verification ==="
ssh $ROUTER "cat /jffs/logs/router.log"
