#!/bin/sh
. /jffs/scripts/log.sh

LOCK=/tmp/watchdog.lock
SETUP_DONE=/tmp/setup_done

[ ! -f "$SETUP_DONE" ] && exit 0
[ -f "$LOCK" ] && exit 0
touch "$LOCK"

ETH1_IP=$(ifconfig eth1 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)

# (a) eth1 has no IP
if [ -z "$ETH1_IP" ]; then
    log "watchdog" "eth1 has no IP - running udhcpc"
    udhcpc -i eth1 -q -s /jffs/udhcpc.script
    sleep 3
    ETH1_IP=$(ifconfig eth1 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)
    if [ -n "$ETH1_IP" ]; then
        log "watchdog" "eth1 recovered with IP $ETH1_IP"
    else
        log "watchdog" "eth1 still has no IP - hotspot likely offline"
    fi
fi

# (b) Flush PREROUTING - log if anything was there
PREROUTING_BEFORE=$(iptables -t nat -L PREROUTING -n)
iptables -t nat -F PREROUTING
PREROUTING_AFTER=$(iptables -t nat -L PREROUTING -n)
if [ "$PREROUTING_BEFORE" != "$PREROUTING_AFTER" ]; then
    log "watchdog" "flushed PREROUTING rules - before:"
    echo "$PREROUTING_BEFORE"
fi

# (c) MASQUERADE missing
MASQ=$(iptables -t nat -L POSTROUTING -n | grep MASQUERADE)
if [ -z "$MASQ" ]; then
    log "watchdog" "MASQUERADE missing - restoring NAT rules"
    iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE
    iptables -D FORWARD -i br0 -o eth1 -j ACCEPT 2>/dev/null
    iptables -D FORWARD -i eth1 -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -A FORWARD -i br0 -o eth1 -j ACCEPT
    iptables -A FORWARD -i eth1 -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    log "watchdog" "NAT rules restored:"
    iptables -t nat -L POSTROUTING -n -v
fi

# (d) dnsmasq not running
if ! pidof dnsmasq > /dev/null; then
    log "watchdog" "dnsmasq not running - restarting"
    dnsmasq --log-async --no-resolv --server=8.8.8.8 --server=8.8.4.4 \
      --conf-file=/jffs/dnsmasq-dhcp.conf --interface=br0 --interface=lo \
      --bind-interfaces --port=53
    log "watchdog" "dnsmasq restarted with pid: $(pidof dnsmasq)"
fi

rm -f "$LOCK"
