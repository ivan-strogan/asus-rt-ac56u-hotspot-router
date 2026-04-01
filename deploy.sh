#!/bin/bash
# Deploy scripts to RT-AC56U
# Run from your Mac: bash deploy.sh
# Requires SSH access to the router at 192.168.1.1

ROUTER="admin@192.168.1.1"

echo "=== Deploying to $ROUTER ==="

# Ensure directories exist on router
ssh $ROUTER "mkdir -p /jffs/scripts /jffs/previous"

# Upload all scripts
echo "--- Uploading scripts ---"
scp scripts/log.sh            $ROUTER:/jffs/scripts/log.sh
scp scripts/init-start        $ROUTER:/jffs/scripts/init-start
scp scripts/firewall-start    $ROUTER:/jffs/scripts/firewall-start
scp scripts/services-start    $ROUTER:/jffs/scripts/services-start
scp scripts/wan-watchdog.sh   $ROUTER:/jffs/scripts/wan-watchdog.sh
scp scripts/self-update.sh    $ROUTER:/jffs/scripts/self-update.sh
scp scripts/dnsmasq-dhcp.conf $ROUTER:/jffs/dnsmasq-dhcp.conf
scp scripts/udhcpc.script     $ROUTER:/jffs/udhcpc.script

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

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Verify:"
echo "  cru l              - watchdog cron job present"
echo "  ls /jffs/scripts/  - all scripts uploaded"
