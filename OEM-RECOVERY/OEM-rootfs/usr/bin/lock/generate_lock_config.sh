#!/bin/sh

LOCK_CONFIG_PATH=/etc/lock_config

CFG=/etc/board.json

. /usr/share/libubox/jshn.sh

[ -f $CFG ] || exit 1

generate_static_network() {
	uci -c $LOCK_CONFIG_PATH -q batch <<EOF
delete network.loopback
set network.loopback='interface'
set network.loopback.ifname='lo'
set network.loopback.proto='static'
set network.loopback.ipaddr='127.0.0.1'
set network.loopback.netmask='255.0.0.0'
delete network.globals
set network.globals='globals'
EOF
}

generate_network() {
	json_select network
	json_select $1
	json_get_vars ifname create_vlan macaddr
	json_select ..
	json_select ..

	[ -n "$ifname" ] || return

	uci -c $LOCK_CONFIG_PATH -q batch <<EOF
delete network.$1
EOF

	case $1 in
	lan) uci -c $LOCK_CONFIG_PATH  -q batch <<EOF
set network.lan='interface'
set network.lan.ifname='eth0'
set network.lan.force_link=1
set network.lan.macaddr='$macaddr'
set network.lan.type='bridge'
set network.lan.proto='static'
set network.lan.ipaddr='192.168.3.1'
set network.lan.netmask='255.255.255.0'
EOF
		;;
	wan*) uci -c $LOCK_CONFIG_PATH -q batch <<EOF
set network.$1='interface'
set network.$1.ifname='$ifname'
set network.$1.force_link=1
set network.$1.proto='none'
set network.$1.macaddr='$macaddr'
set network.$1.proto='dhcp'
set network.$1.binding=''
set network.$1.defaultroute='1'
delete network.$1_ip6
set network.$1_ip6='interface'
set network.$1_ip6.ifname='$ifname'
set network.$1_ip6.defaultroute='1'
set network.$1_ip6.proto='dhcpv6'
set network.$1_ip6.reqprefix='auto'
set network.$1_ip6.reqaddress='none'
EOF
		;;
	esac

}

json_init
json_load "$(cat ${CFG})"

generate_static_network

json_get_keys keys network
for key in $keys; do generate_network $key; done

uci -c $LOCK_CONFIG_PATH commit
