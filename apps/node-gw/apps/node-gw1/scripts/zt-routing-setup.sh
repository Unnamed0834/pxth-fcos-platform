



set -euo pipefail

echo "=== ZeroTier Gateway L3 Routing Setup ==="


echo 1 > /proc/sys/net/ipv4/ip_forward
echo "IP forwarding enabled"


echo "Waiting for ZeroTier network to initialize..."
for i in $(seq 1 60); do
    if /opt/bin/zerotier-cli listnetworks | grep -q "0000000000000000"; then
        echo "ZeroTier network joined successfully"
        break
    fi
    echo "Attempt $i/60: Waiting for network join..."
    sleep 2
done





echo "Configuring ZeroTier network for L3 routing..."
/opt/bin/zerotier-cli set 0000000000000000 allowManaged=1 2>/dev/null && echo "allowManaged=1 set" || echo "Failed to set allowManaged=1"
/opt/bin/zerotier-cli set 0000000000000000 allowDefault=0 2>/dev/null && echo "allowDefault=0 set" || echo "Failed to set allowDefault=0"


ZT_INTERFACE=$(ip -o link show | grep -i zerotier | awk -F': ' '{print $2}' | sed 's/@.*//')
if [ -z "$ZT_INTERFACE" ]; then
    echo "ERROR: ZeroTier interface not found"
    exit 1
fi
echo "ZeroTier interface: $ZT_INTERFACE"


ip link set dev "$ZT_INTERFACE" mtu 1500
sysctl -w net.ipv4.ip_no_pmtu_disc=0 2>/dev/null || true
echo "ZT interface MTU set to 1500 (PMTUD enabled)"



echo "Setting up forwarding rules..."


iptables -F FORWARD 2>/dev/null || true


iptables -A FORWARD -i "$ZT_INTERFACE" -o eth0 -d 203.0.113.0/24 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -s 203.0.113.0/24 -o "$ZT_INTERFACE" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT


iptables -A FORWARD -j DROP

echo "Forwarding rules configured (ZT ↔ VLAN 1002 only)"


echo "=== ZeroTier Gateway Status ==="
echo "Node Info:"
/opt/bin/zerotier-cli info 2>/dev/null || echo "Failed to get node info"
echo "Networks:"
/opt/bin/zerotier-cli listnetworks 2>/dev/null || echo "Failed to list networks"
echo "Network Interfaces:"
ip addr show | grep -E "inet.*eth0|inet.*zt" || echo "No network interfaces found"
echo "Forwarding Rules:"
iptables -L FORWARD -n -v || echo "Failed to list rules"
echo "IP Forwarding Status: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "=== End Status ==="


if ip link show | grep -q "zt"; then
    echo "SUCCESS: ZeroTier interface is active"
else
    echo "WARNING: ZeroTier interface not found - check network authorization in ZeroTier control panel"
fi

echo "=== ZeroTier Gateway L3 Routing Setup Complete ==="
