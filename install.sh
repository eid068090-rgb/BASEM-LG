#!/bin/sh
set -e

opkg update
opkg install lldpd
/etc/init.d/lldpd enable
/etc/init.d/lldpd restart

mkdir -p /www/cgi-bin
cp ./basem-lldp /www/cgi-bin/basem-lldp
chmod 755 /www/cgi-bin/basem-lldp

echo ""
echo "LLDP installed. Test with:"
echo "  lldpcli show neighbors"
echo "  lldpcli -f json0 show neighbors details"
echo ""
echo "Optional token:"
echo "  printf '%s' 'CHANGE_ME' > /etc/basem-lldp.token"
echo "  chmod 600 /etc/basem-lldp.token"
echo ""
echo "Endpoint: http://ROUTER_IP/cgi-bin/basem-lldp"
