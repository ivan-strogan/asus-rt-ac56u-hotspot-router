# ASUS RT-AC56U - iPhone Hotspot Router

Turns an ASUS RT-AC56U into a proper NAT router using an iPhone hotspot as its internet uplink. All devices on the LAN get internet through the iPhone connection without any manual intervention after boot.

This is not officially supported by the firmware. It works by combining Repeater mode (which handles WPA2 auth to the iPhone) with custom JFFS scripts that bolt NAT on top.

---

## Hardware & Software

| | |
|---|---|
| Router | ASUS RT-AC56U |
| Firmware | Asuswrt-Merlin 384.6 |
| iPhone | iPhone 13 Mini (or any iPhone with Personal Hotspot) |
| iPhone Setting | **Maximize Compatibility = ON** (forces 2.4GHz - required) |

---

## How It Works

```
iPhone (hotspot)
    |
    | WiFi 2.4GHz - eth1 gets DHCP lease from iPhone
    |
  Router (192.168.1.1)
    |
    |- WiFi 2.4GHz AP  - SSID: YourHotspot_RPT
    |- WiFi 5GHz AP    - SSID: YourHotspot_RPT5G
    |- LAN Ethernet ports
    |
  Devices get 192.168.1.100-200 via DHCP
```

The firmware's Repeater mode handles connecting to the iPhone and authenticating. The custom scripts then:
1. Remove `eth1` from the bridge so it acts as WAN
2. Get a DHCP lease from the iPhone on `eth1`
3. Set up NAT so LAN devices can reach the internet
4. Run `dnsmasq` for DHCP and DNS on the LAN

A watchdog runs every minute to detect and fix any iptables rules the firmware resets.

---

## Interface Reference

| Interface | Role |
|---|---|
| `eth1` | 2.4GHz radio - iPhone uplink (WAN) |
| `eth2` | 5GHz radio - LAN AP |
| `wl0.1` | 2.4GHz virtual AP - LAN AP |
| `br0` | LAN bridge (192.168.1.1) |
| `vlan1` | Physical LAN Ethernet ports |
| `vlan2` | Physical WAN port (unused) |

---

## Initial Setup

### Step 1 - Flash Asuswrt-Merlin

1. Download Merlin 384.6 for the RT-AC56U from the Merlin firmware site
2. In the stock ASUS firmware, go to **Administration -> Firmware Upgrade**
3. Upload the Merlin `.trx` file and wait for the router to reboot

### Step 2 - Enable JFFS

JFFS is the persistent storage partition where custom scripts live.

1. Log into the router at `http://192.168.1.1`
2. Go to **Administration -> System**
3. Enable **JFFS custom scripts and configs** -> Apply
4. Reboot the router

### Step 3 - Configure Repeater Mode

This is what makes the router connect to the iPhone hotspot.

1. On your iPhone, go to **Settings -> Personal Hotspot**
2. Turn on **Maximize Compatibility** - this forces 2.4GHz which the router requires
3. Turn on Personal Hotspot
4. On the router, go to **Administration -> Operation Mode**
5. Select **Repeater Mode**
6. Scan for networks and select your iPhone hotspot SSID
7. Enter the hotspot password
8. Apply - the router will reboot

After reboot, the router will automatically reconnect to the iPhone hotspot.

### Step 4 - Deploy the Scripts

From your Mac, with the router reachable at `192.168.1.1`:

```bash
git clone https://github.com/ivan-strogan/asus-rt-ac56u-hotspot-router.git
cd asus-rt-ac56u-hotspot-router
bash deploy.sh
```

`deploy.sh` will:
1. Upload all scripts to `/jffs/scripts/` on the router
2. Set correct permissions
3. Reboot the router
4. Wait 3 minutes then automatically print `/jffs/logs/router.log` so you can confirm everything came up correctly

**First time only** - set up SSH key auth so deploy.sh runs without password prompts:
```bash
ssh-copy-id admin@192.168.1.1
```

Then add this to `~/.ssh/config` (required for older dropbear compatibility):
```
Host 192.168.1.1
    PubkeyAcceptedAlgorithms +ssh-rsa
    HostkeyAlgorithms +ssh-rsa
```

### Step 5 - Install git HTTPS transport (one-time)

The self-update script clones from GitHub over HTTPS. The base Entware `git` package does not include the HTTPS transport helper. Without it, every clone attempt fails with:

```
git: 'remote-https' is not a git command. See 'git --help'.
```

**Why DNS doesn't work out of the box for the router itself:**

`/etc/resolv.conf` is a symlink to `/rom/etc/resolv.conf` on the read-only ROM filesystem, hardcoded to `127.0.0.1`. The firmware runs its own dnsmasq with minimal arguments (`dnsmasq --log-async`) and no upstream servers configured — so DNS queries to `127.0.0.1` silently fail. This breaks `opkg`, `git clone`, and any other tool that needs to resolve hostnames on the router itself.

LAN clients are unaffected — they receive `8.8.8.8` directly via DHCP and bypass the router's dnsmasq for DNS entirely.

`init-start` replaces the symlink with a real file pointing to `8.8.8.8` on every boot, fixing this permanently. For this one-time manual install, do the same before running opkg:

```bash
ssh admin@192.168.1.1
rm /etc/resolv.conf && echo "nameserver 8.8.8.8" > /etc/resolv.conf
opkg update && opkg install git-http
```

`git-http` pulls in `ca-bundle` and `libcurl` automatically. These are stored in `/jffs/entware` and survive reboots — this step only needs to be done once.

### Step 6 - Verify

After `deploy.sh` completes, the log output is printed automatically. You can also check the log manually:

```bash
ssh admin@192.168.1.1
cat /jffs/logs/router.log
```

---

## Health Check

Run these commands over SSH to confirm everything is working correctly:

```bash
# eth1 should NOT be in the bridge
brctl show

# Default route must go via eth1
route -n

# eth1 must have an IP from the iPhone
ifconfig eth1 | grep inet

# br0 must be the LAN address
ifconfig br0 | grep inet

# Must be 1
cat /proc/sys/net/ipv4/ip_forward

# MASQUERADE rule must be present
iptables -t nat -L POSTROUTING -n

# Should be clean (no DNS or HTTP redirects)
iptables -t nat -L PREROUTING -n

# Watchdog cron job must be listed
cru l
```

---

## Accessing the Router

| Method | Address |
|---|---|
| Ethernet to LAN port | `ssh admin@192.168.1.1` |
| Connected to router WiFi | `ssh admin@192.168.1.1` |
| From iPhone hotspot side | `ssh admin@<eth1 IP>` - fallback if LAN unreachable |

To find the `eth1` IP: `ifconfig eth1 | grep inet`

---

## How the Watchdog Works

The firmware periodically runs its own scripts that break the NAT setup - removing the MASQUERADE rule and injecting bad DNS/HTTP redirect rules. The watchdog detects and fixes this automatically.

Every minute it checks:

1. **eth1 has an IP** - if not (iPhone hotspot disconnected), runs `udhcpc` to re-acquire a lease
2. **Bad PREROUTING rules** - flushes the entire PREROUTING chain (`iptables -t nat -F PREROUTING`). The firmware injects DNS and HTTP redirect rules into PREROUTING that intercept LAN traffic. No PREROUTING rules are needed for this setup so flushing the whole chain is simpler and catches any variant the firmware injects.
3. **MASQUERADE present** - if missing, re-adds it along with the FORWARD rules (idempotent - won't stack duplicates)
4. **dnsmasq running** - restarts it if it died

The watchdog won't run until `services-start` has finished its initial setup (uses a `/tmp/setup_done` flag to avoid a startup race).

---

## Boot Sequence

After reboot allow **2-3 minutes** before testing:

1. Router boots, firmware connects to iPhone via Repeater mode (automatic)
2. `init-start` runs - mounts Entware (`/jffs/entware` -> `/opt`) and replaces `/etc/resolv.conf` symlink with a real file pointing to `8.8.8.8` so the router itself can resolve DNS
3. `firewall-start` runs - opens SSH on the LAN
4. `services-start` runs:
   - Waits for `eth1` to get an IP from the iPhone
   - Syncs the clock via NTP (router boots with clock at firmware build date ~2018 - SSL cert validation fails without this)
   - Sets up NAT and IP forwarding
   - Starts dnsmasq for LAN DHCP and DNS
   - Registers the watchdog cron job
   - Runs self-update check if 7+ days since last check

If the iPhone hotspot is off when the router boots, `services-start` will wait indefinitely for it to become available.

**Why NTP matters:** The router has no battery-backed RTC. On every boot the clock starts at the firmware build date (May 2018). SSL certificate validation checks the current date against the cert's validity window — without NTP sync, all HTTPS connections fail with `SSL certificate problem: certificate is not yet valid`.

---

## Useful Diagnostic Commands

```bash
# Check wireless connection status to iPhone
wl -i eth1 status

# Check bridge members (eth1 should not be listed)
brctl show

# Check routing table (default route should be via eth1)
route -n

# Check IP forwarding
cat /proc/sys/net/ipv4/ip_forward

# Check NAT rules
iptables -t nat -L POSTROUTING -n -v

# Check for bad firmware rules
iptables -t nat -L PREROUTING -n

# Check cron jobs (watchdog should be listed)
cru l

# Scan for iPhone hotspot
wl -i eth1 scan && sleep 3 && wl -i eth1 scanresults | grep -A3 "YOUR_HOTSPOT_SSID"
```

---

## Manual Fix

If internet breaks before the watchdog catches it, run this:

```bash
iptables -t nat -F PREROUTING
iptables -t nat -D POSTROUTING -o eth1 -j MASQUERADE 2>/dev/null
iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE
iptables -D FORWARD -i br0 -o eth1 -j ACCEPT 2>/dev/null
iptables -D FORWARD -i eth1 -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
iptables -A FORWARD -i br0 -o eth1 -j ACCEPT
iptables -A FORWARD -i eth1 -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
killall dnsmasq 2>/dev/null
sleep 2
dnsmasq --log-async --no-resolv --server=8.8.8.8 --server=8.8.4.4 \
  --conf-file=/jffs/dnsmasq-dhcp.conf --interface=br0 --interface=lo \
  --bind-interfaces --port=53
```

---

## Important Notes

- If the iPhone hotspot password changes, update it via **Administration -> Operation Mode -> Repeater** in the GUI at `http://192.168.1.1`
- **Maximize Compatibility must be ON** on the iPhone
- To reboot the router: `reboot`
- To power off: pull the plug - no shutdown command on this firmware
- JFFS storage survives reboots. Factory reset does NOT wipe JFFS unless you select **Format JFFS** during reset
