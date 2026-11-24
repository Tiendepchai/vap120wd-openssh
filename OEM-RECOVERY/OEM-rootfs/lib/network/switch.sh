#!/bin/sh

restore6855Esw()
{
	echo "restore GSW to dump switch mode"
	#port matrix mode
	switch reg w 2004 ff0000 #port0
	switch reg w 2104 ff0000 #port1
	switch reg w 2204 ff0000 #port2
	switch reg w 2304 ff0000 #port3
	switch reg w 2404 ff0000 #port4
	switch reg w 2504 ff0000 #port5
	switch reg w 2604 ff0000 #port6
	switch reg w 2704 ff0000 #port7

	#LAN/WAN ports as transparent mode
	switch reg w 2010 810000c0 #port0
	switch reg w 2110 810000c0 #port1
	switch reg w 2210 810000c0 #port2
	switch reg w 2310 810000c0 #port3
	switch reg w 2410 810000c0 #port4
	switch reg w 2510 810000c0 #port5
	switch reg w 2610 810000c0 #port6
	switch reg w 2710 810000c0 #port7
	
	#clear mac table if vlan configuration changed
	switch clear
	switch vlan clear 
}

config6855Esw()
{
	if [ "$1" = "LLLLW" ]; then
		#VLAN member port
		switch vlan set 1 1 11110011
		switch vlan set 2 2 00001100
		#set PVID
		switch vlan pvid 4 2
		switch vlan pvid 5 2
		#LAN/WAN ports as security mode
		switch reg w 2004 ff0003 #port0
		switch reg w 2104 ff0003 #port1
		switch reg w 2204 ff0003 #port2
		switch reg w 2304 ff0003 #port3
		switch reg w 2404 ff0003 #port4
		switch reg w 2504 ff0003 #port5
		switch reg w 2604 ff0003 #port6
	elif [ "$1" = "WLLLL" ]; then
		#VLAN member port
		switch vlan set 1 1 01111011
		switch vlan set 2 2 10000100
		#set PVID
		switch vlan pvid 2 1
		switch vlan pvid 3 1
		switch vlan pvid 4 1
		switch vlan pvid 0 2
		switch vlan pvid 5 2
		#LAN/WAN ports as security mode
		switch reg w 2004 ff0003 #port0
		switch reg w 2104 ff0003 #port1
		switch reg w 2204 ff0003 #port2
		switch reg w 2304 ff0003 #port3
		switch reg w 2404 ff0003 #port4
		switch reg w 2504 ff0003 #port5
		switch reg w 2604 ff0003 #port6
	elif [ "$1" = "VTAP" ]; then
		# Port 6 as Userport
		switch reg w 0x2610 0x81000000
		#VLAN member port
		switch vlan set 1 1 00010010 # port 3, 6 vlan 1
		switch vlan set 2 2 00001010 # port 4, 6 vlan 2
		switch vlan set 3 3 00100100 # port 2, 5 vlan 3
		#set PVID
		switch vlan pvid 3 1
		switch vlan pvid 4 2
		switch vlan pvid 2 3
		switch vlan pvid 5 3
		#LAN/WAN ports as security mode
		switch reg w 2004 ff0003 #port0
		switch reg w 2104 ff0003 #port1
		switch reg w 2204 ff0003 #port2
		switch reg w 2304 ff0003 #port3
		switch reg w 2404 ff0003 #port4
		switch reg w 2504 ff0003 #port5
		switch reg w 2604 20ff0003 #port6 security mode + tagged
	elif [ "$1" = "LLWLL" ]; then
		#VLAN member port
		switch vlan set 1 1 11011011
		switch vlan set 2 2 00100100
		#set PVID
		switch vlan pvid 3 1
		switch vlan pvid 4 1
		switch vlan pvid 6 1
		switch vlan pvid 2 2
		switch vlan pvid 5 2
		#LAN/WAN ports as security mode
		switch reg w 2004 ff0003 #port0
		switch reg w 2104 ff0003 #port1
		switch reg w 2204 ff0003 #port2
		switch reg w 2304 ff0003 #port3
		switch reg w 2404 ff0003 #port4
		switch reg w 2504 ff0003 #port5
		switch reg w 2604 ff0003 #port6
	fi
}

setup_switch()
{
	echo "7621 use an independent gmac as lan"
	# restore6855Esw
	#config6855Esw VTAP

	# AP-463: mesh 3 LAN agent
    MapEnable=$(wificonf -f /etc/mapd_cfg.txt get MapEnable)
    DeviceRole=$(wificonf -f /etc/mapd_cfg.txt get DeviceRole)
	lock_status=$(cof_cli read LockStatus)
    if [ $MapEnable == "1" ] && [ $DeviceRole == "2" ]
    then
        echo "==> Map Enable, Device role is Agent"
		if [ "$lock_status" = "1" ];then
			echo "==> Switch Config Locked Agent"
			restore6855Esw
        	config6855Esw LLWLL
		# else
		# 	config6855Esw WLLLL
		fi
    else
        echo "==> Map Disable or Device role is Controller"
        #  config6855Esw VTAP
    fi

	if [ "$lock_status" = "1" ];then
		/usr/bin/lock/lock_action.sh switch_acl_on
	fi
}

reset_switch()
{
	echo "7621 use an independent gmac as lan & wan"
	restore6855Esw
}
