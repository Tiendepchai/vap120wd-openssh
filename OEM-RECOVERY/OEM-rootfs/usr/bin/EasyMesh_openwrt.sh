#!/bin/sh
RED='\033[0;31m'
NC='\033[0m'
echo -e "----- ${RED}EasyMesh SCRIPT${NC} -----"
killall -15 mapd
killall -15 wapp
killall -15 p1905_managerd
killall -15 bs20
rm -rf /tmp/wapp_ctrl
echo -e "----- ${RED}killed all apps ${NC} -----"
check_default="$1"
default_map_dev_role=2
default_map_ap_rssi_th=-70
default_map_steer_enable=1
default_map_CUOverloadTh_2G=90
default_map_CUOverloadTh_5G_L=85
default_map_CUOverloadTh_5G_H=85
default_rssi_age_limit=8
default_map_bh_priority_2g=3
default_map_bh_priority_5gl=1
default_map_bh_priority_5gh=1
default_map_channel_planning=1
default_map_dhcp_ctl=1
default_radio_band="24G;5G;5G;"
default_LowRSSIAPSteerEdge_root=20
default_reset_btm_csbc_at_join=1
default_BTMUnfriendlyTime=120
default_BTMAssociationTime=6
default_LegacyAssociationTime=10
default_KeepStaTime=6
ra_band=$default_radio_band
NetworkOptimizationEnabled=0
NtwrkOptBootupWaitTime=45
NtwrkOptConnectWaitTime=5
NtwrkOptDisconnectWaitTime=10
NtwrkOptPeriodicity=3600
NetworkOptimizationScoreMargin=100
default_rssi_threshold_2g=-80
default_rssi_threshold_5g=-80
default_auto_bhswitch=1
rssi_2g_thresh=$default_rssi_threshold_2g
rssi_5g_thresh=$default_rssi_threshold_5g
default_ch_pl_init_timeout=120
default_ThirdPartyConnection=0
Third_Party_Connection=$default_ThirdPartyConnection
if [ ! -f "/etc/mapd_cfg.txt" ];then
	#GET EasyMesh settings from dev1 i.e. 2860 mapped DAT file mentioned in l1profile.dat file.
	map_enable=$(nvram_get 2860 MapEnable)
	map_dev_role=$default_map_dev_role
	bs_enable=$(nvram_get 2860 BSEnable)
	map_turnkey=$(nvram_get 2860 MAP_Turnkey)
elif [ "$check_default" = "default" ];then
	echo "Reset to default EasyMesh settings!"
	map_enable=$(wificonf -f /etc/mapd_cfg.txt get MapEnable)
	#AP-158
	#map_dev_role=$(wificonf -f /etc/mapd_cfg.txt get DeviceRole)
	map_dev_role=$default_map_dev_role
	map_ChPlanningIdleByteCount=$(wificonf -f /etc/mapd_cfg.txt get ChPlanningIdleByteCount)
	map_ChPlanningIdleTime=$(wificonf -f /etc/mapd_cfg.txt get ChPlanningIdleTime)
	map_ChPlanningUserPreferredChannel5G=$(wificonf -f /etc/mapd_cfg.txt get ChPlanningUserPreferredChannel5G)
	map_ChPlanningUserPreferredChannel2G=$(wificonf -f /etc/mapd_cfg.txt get ChPlanningUserPreferredChannel2G)
	map_bss_config_priority=$(wificonf -f /etc/map_cfg.txt get bss_config_priority)
	NtwrkOptBootupWaitTime=45
	NtwrkOptConnectWaitTime=5
	NtwrkOptDisconnectWaitTime=10
	NtwrkOptPeriodicity=3600
	NetworkOptimizationScoreMargin=100
	Third_Party_Connection=$default_ThirdPartyConnection
	AutoBHSwitch=$default_auto_bhswitch
else
	map_enable=$(wificonf -f /etc/mapd_cfg.txt get MapEnable)
	map_dev_role=$(wificonf -f /etc/mapd_cfg.txt get DeviceRole)
	bs_enable=$(wificonf -f /etc/mapd_cfg.txt get BSEnable)
	map_turnkey=$(nvram_get 2860 MAP_Turnkey)
	ra_band=$(wificonf -f /etc/map_cfg.txt get radio_band)
	AutoBHSwitch=$(wificonf -f /etc/mapd_cfg.txt get AutoBHSwitching)
	band_switch_time=$(wificonf -f /etc/mapd_cfg.txt get BandSwitchTime)
	NtwrkOptBootupWaitTime=$(wificonf -f /etc/mapd_cfg.txt get NtwrkOptBootupWaitTime)
	NtwrkOptConnectWaitTime=$(wificonf -f /etc/mapd_cfg.txt get NtwrkOptConnectWaitTime)
	NtwrkOptDisconnectWaitTime=$(wificonf -f /etc/mapd_cfg.txt get NtwrkOptDisconnectWaitTime)
	NtwrkOptPeriodicity=$(wificonf -f /etc/mapd_cfg.txt get NtwrkOptPeriodicity)
	NetworkOptimizationScoreMargin=$(wificonf -f /etc/mapd_cfg.txt get NetworkOptimizationScoreMargin)
	rssi_2g_thresh=$(wificonf -f /etc/mapd_cfg.txt get ScanThreshold2g)
	rssi_5g_thresh=$(wificonf -f /etc/mapd_cfg.txt get ScanThreshold5g)
	ra_band=$(nvram_get 2860 radio_band)
	Third_Party_Connection=$(wificonf -f /etc/mapd_cfg.txt get ThirdPartyConnection)
fi

if [ -z "$ra_band" ];
then
        ra_band=$default_radio_band
fi

ctrlr_al_mac=$(cat /sys/class/net/br-lan/address)
agent_al_mac=$(cat /sys/class/net/br-lan/address)
if [ -f "/etc/map_cfg.txt" ];then
	map_bss_config_priority=$(wificonf -f /etc/map_cfg.txt get bss_config_priority)
fi
if [ -z "$map_bss_config_priority" ];then
	map_bss_config_priority="rax0;rax1;rax2;rax3;ra0;ra1;ra2;ra3;apclix0;apcli0"
fi

#wificonf -f /etc/mapd_cfg.txt set bss_config_priority $map_bss_config_priority
#if [ ! -f "/etc/map_cfg.txt" -o "$check_default" = "default" ];then
#	echo "Make map_cfg.txt"

# AP-229
value_map_root=$(wificonf -f /etc/map_cfg.txt get map_root)
value_map_agent=$(wificonf -f /etc/map_cfg.txt get map_agent)
lan1=$(wificonf -f /etc/map_cfg.txt get lan1)
lan2=$(wificonf -f /etc/map_cfg.txt get lan2)

# AP-469
hwnat_status=$(uci -q get hwnat.global.enabled)

echo "# Controller's ALID
map_controller_alid=$ctrlr_al_mac

# Has MAP agent on this device
map_agent=$value_map_agent

# This device is a MAP root
map_root=$value_map_root

# Agent's ALID
map_agent_alid=$agent_al_mac

# Default Back-haul Type
bh_type=wifi

#Config Band setting of each Radio
radio_band=$ra_band

#bridge interface
br_inf=br-lan

#lan interface
#lan=eth0
lan1=$lan1
lan2=$lan2

bss_config_priority=$map_bss_config_priority
" > /etc/map_cfg.txt
#fi

if [ ! -f "/etc/mapd_cfg.txt" -o "$check_default" = "default" ];then
	echo "Make /etc/mapd_cfg.txt"
echo "#lan interface for device
lan_interface=eth0
#wan interface for device
wan_interface=eth1
MapEnable=$map_enable
DeviceRole=$map_dev_role
APSteerRssiTh=$default_map_ap_rssi_th
ChPlanningEnable=$default_map_channel_planning
BhPriority2G=$default_map_bh_priority_2g
BhPriority5GL=$default_map_bh_priority_5gl
BhPriority5GH=$default_map_bh_priority_5gh
ChPlanningIdleByteCount=$map_ChPlanningIdleByteCount
ChPlanningIdleTime=$map_ChPlanningIdleTime
SteerEnable=$default_map_steer_enable
CUOverloadTh_2G=$default_map_CUOverloadTh_2G
CUOverloadTh_5G_L=$default_map_CUOverloadTh_5G_L
CUOverloadTh_5G_H=$default_map_CUOverloadTh_5G_H
ChPlanningUserPreferredChannel5G=$map_ChPlanningUserPreferredChannel5G
ChPlanningUserPreferredChannel2G=$map_ChPlanningUserPreferredChannel2G
ChPlanningInitTimeout=$default_ch_pl_init_timeout
NetworkOptimizationEnabled=$NetworkOptimizationEnabled
NtwrkOptBootupWaitTime=$NtwrkOptBootupWaitTime
NtwrkOptConnectWaitTime=$NtwrkOptConnectWaitTime
NtwrkOptDisconnectWaitTime=$NtwrkOptDisconnectWaitTime
NtwrkOptPeriodicity=$NtwrkOptPeriodicity
NetworkOptimizationScoreMargin=$NetworkOptimizationScoreMargin
DhcpCtl=$default_map_dhcp_ctl
AutoBHSwitching=$AutoBHSwitch
BandSwitchTime=$band_switch_time
ScanThreshold2g=$rssi_2g_thresh
ScanThreshold5g=$rssi_5g_thresh
ThirdPartyConnection=$Third_Party_Connection
bss_config_priority=$map_bss_config_priority
" > /etc/mapd_cfg.txt
fi

ulimit -c unlimited
if [ ! -f "/etc/mapd_strng.conf" -o "$check_default" = "default" ];then
	echo "Make mapd_strng.conf"
	rssi=$((default_map_ap_rssi_th + 94))
echo "LowRSSIAPSteerEdge_RE=$rssi
LowRSSIAPSteerEdge_root=$default_LowRSSIAPSteerEdge_root
CUOverloadTh_2G=$default_map_CUOverloadTh_2G
CUOverloadTh_5G_L=$default_map_CUOverloadTh_5G_L
CUOverloadTh_5G_H=$default_map_CUOverloadTh_5G_H
RSSIAgeLimit=$default_rssi_age_limit
BTMUnfriendlyTime=$default_BTMUnfriendlyTime
reset_btm_csbc_at_join=$default_reset_btm_csbc_at_join
BTMAssociationTime=$default_BTMAssociationTime
LegacyAssociationTime=$default_LegacyAssociationTime
KeepStaTime=$default_KeepStaTime

" > /etc/mapd_strng.conf
fi

ModifySwitchReg()
{
	# To make switch related MC register setting for eth on platform mt7621
	# support lsdk
	if [ -f /sbin/config.sh ]; then     
	  echo "easymesh in lsdk ver"
	  . /sbin/config.sh
	fi
	
	# support openwrt 
	if [ -f /etc/kernel.config ]; then                         
	  echo "easymesh in openwrt ver"
	  . /etc/kernel.config
	fi
	
	if [ "$CONFIG_RALINK_MT7621" = "y" -o "$CONFIG_MT7621_ASIC" = "y" ]; then
	  echo "easymesh board name is 7621"
	  switch reg w 10 ffffffe0
	  switch reg w 34 8160816
	fi
}

ModifySwitchReg

StartStandAloneBS()
{
        sleep 3
        echo "WAPP starting..."
        wapp_openwrt.sh > /dev/null
        sleep 3
        echo "BS2.0 Daemon starting..."
        bs20 &
        sleep 3
	iwpriv ra0 set DisConnectAllSta=
	iwpriv ra1 set DisConnectAllSta=
	iwpriv ra2 set DisConnectAllSta=
	iwpriv ra3 set DisConnectAllSta=
	iwpriv rax0 set DisConnectAllSta=
	iwpriv rax1 set DisConnectAllSta=
	iwpriv rax2 set DisConnectAllSta=
	iwpriv rax3 set DisConnectAllSta=
	#iwpriv rai0 set DisConnectAllSta=
	#iwpriv rai1 set DisConnectAllSta=
	#iwpriv rai2 set DisConnectAllSta=
	#iwpriv rai3 set DisConnectAllSta=

        echo "Stand Alone BS2.0 is ready"
}


if [ "$map_enable" = "1" ];then
	echo "EasyMesh is enabled!"
else
	echo "EasyMesh is disabled!"
        if [ "$bs_enable" = "1" -a "$map_turnkey" = "0" ];then
                echo "Stand Alone BS is enabled$"
                StartStandAloneBS
		sleep 1
		mkdir /libmapd
		cp /usr/lib/libmapd_interface_client.so /libmapd/
	fi
	rmmod mapfilter
	modprobe mtfwd
	sleep 1
	fwdd -p ra0 apcli0 -p rai0 apclii0 -p rax0 apclix0 -p wlan0 wlan-apcli0 -e eth0 5G&
	if [ "$bs_enable" != "1" ];then
		wapp_openwrt.sh
	fi
	
	# AP-398
	ifconfig ra3 down
    
    # AP-398: Disable mesh at agent
    ifconfig apcli0 down
    ifconfig apclix0 down

    # AP-320: hwnat enable
    hwnat-enable.sh

    # AP-523: up eth1
    ifconfig eth1 up

    # AP-657: down ra3 (bhbss)
	ifconfig ra3 down

    exit 1

fi
sleep 1

mkdir /libmapd
cp /usr/lib/libmapd_interface_client.so /libmapd/
echo "kill fwdd daemon and remove mtfwd module"
killall -15 fwdd
sleep 1
rmmod mtfwd
modprobe mapfilter
#Enable QuickChChange feature.
wificonf -f /etc/mapd_cfg.txt set MAP_QuickChChange 1
ApCliIntfUp()
{
	ifconfig apcli0 up;
	ifconfig apclix0 up;
	#ifconfig apclii0 up;
	#ifconfig apcli1 up;
	#ifconfig wlan-apcli0 up;
	brctl addif br-lan apcli0;
	brctl addif br-lan apclix0;
	#brctl addif br-lan apclii0;
	#brctl addif br-lan apcli1;
	#brctl addif br-lan wlan-apcli0;
	iwpriv apcli0 set ApCliEnable=0;
	iwpriv apclix0 set ApCliEnable=0;
	#iwpriv apclii0 set ApCliEnable=0;
	#iwpriv apcli1 set ApCliEnable=0;
	#iwpriv wlan-apcli0 set ApCliEnable=0;
	sleep 1
	if [ "$check_default" = "default" ];then
		echo "old profile set invalid"
		wificonf -f /etc/mapd_cfg.txt set BhProfile0Valid 0
	fi
}
if [ "$map_dev_role" = "1" ];then
	#Controller
    # AP-523: up eth1
    ifconfig eth1 up

	# turn down APCli interface there instead of easysetup page
	ifconfig apcli0 down;
	ifconfig apclix0 down;
    #ApCliIntfUp
	iwpriv ra0 set fhbss=1;
	iwpriv ra0 set bhbss=0;
	iwpriv ra3 set fhbss=0;
	iwpriv ra3 set bhbss=1;
	#iwpriv rax0 set bhbss=1;
	#iwpriv rai0 set bhbss=1;
	echo "WAPP starting..."
	wapp_openwrt.sh > /dev/null
	sleep 5
	echo "1905 starting..."
	p1905_managerd -r0 -f "/etc/map_cfg.txt" -F "/etc/wts_bss_info_config" > /dev/console&
	sleep 3
	echo "MAP Daemon starting..."
	mapd -G "/etc/wts_bss_info_config" -I "/etc/mapd_cfg.txt" -O "/etc/mapd_strng.conf" -f "/var/log_mapd" > /dev/console&
	ModifySwitchReg
	sleep 3
	iwpriv ra0 set DisConnectAllSta=
	iwpriv ra1 set DisConnectAllSta=
	iwpriv ra2 set DisConnectAllSta=
	iwpriv ra3 set DisConnectAllSta=
	iwpriv rax0 set DisConnectAllSta=
	iwpriv rax1 set DisConnectAllSta=
	iwpriv rax2 set DisConnectAllSta=
	iwpriv rax3 set DisConnectAllSta=
	#iwpriv rai0 set DisConnectAllSta=
	#iwpriv rai1 set DisConnectAllSta=
	#iwpriv rai2 set DisConnectAllSta=
	#iwpriv rai3 set DisConnectAllSta=
	
	# AP-345: hwnat enable
	hwnat-enable.sh

    # AP-533: backup wts_bss_info_config to /overlay/etc/
    if [ ! -f /overlay/etc/wts_bss_info_config ]; then
        echo "[INFO] backup wts_bss_info_config file."
        cp -f /etc/wts_bss_info_config /overlay/etc/
    fi
elif [ "$map_dev_role" = "2" -o "$map_dev_role" = "0" ];then
	# AP-523: down eth1
	lock_status=$(cof_cli read LockStatus)
	if [ ! -f "/etc/lock_config/network" -o "$lock_status" != "1" ]; then
		ifconfig eth1 down
	fi

    #Agent or Auto
	ApCliIntfUp
	echo "WAPP starting..."
	wapp_openwrt.sh > /dev/null
	sleep 5
	echo "1905 starting..."
	p1905_managerd -r1 -f "/etc/map_cfg.txt" -F "/etc/wts_bss_info_config" > /dev/console&
	sleep 3
	echo "MAP_Daemon starting..."
	mapd -G "/etc/wts_bss_info_config" -I "/etc/mapd_cfg.txt" -O "/etc/mapd_strng.conf" -f "/var/log_mapd" > /dev/console&
	ModifySwitchReg
	sleep 3
	
	# AP-345: hwnat disable
	if [ $hwnat_status == "0" ]; then
	    echo "[INFO] agent hwnat disable!"
	    hwnat-disable.sh
	fi
else
	echo "Unknown EasyMesh Device Role!"
fi

#AP-158
# DHCP_CTRL=$(wificonf -f /etc/mapd_cfg.txt get DhcpCtl)
# if [ "$DHCP_CTRL" = "1" ];then
# 	echo "Controller/Agent Enable DHCP Server!"
# 	if [ -z "$(uci -q get network.lan.ipaddr)" ];then
# 		echo "no IP present , reload network ip to 192.168.2.1"
# 		uci -q set network.lan.ipaddr=192.168.2.1; ifconfig br-lan 192.168.2.1 up; uci set dhcp.lan.ignore=0; uci commit; /etc/init.d/dnsmasq reload; /etc/init.d/network reload
# 	else
# 		ifconfig br-lan `uci -q get network.lan.ipaddr` up; uci set dhcp.lan.ignore=1; uci commit; /etc/init.d/dnsmasq reload;
# 		if [ "$check_default" = "default" ];then
# 			/etc/init.d/network reload
# 		fi
# 	fi
# fi
echo -e "----- ${RED}MAP DEVICE STARTED${NC} -----"
sleep 1

# AP-657: Default Enable DHCP server when agent bootup
# Proplem: if mesh at agent done and change role to controller -> dhcp.lan still disable, so need enable dhcp server on controller
dhcp_ignore=$(uci -q get dhcp.lan.ignore)
dhcp_leasetime=$(uci -q get dhcp.lan.leasetime)
if [ ! -f "/tmp/vt_check_mesh_agent.x" ]; then
	if [ "$map_enable" = "1" -a "$map_dev_role" = "2" ]; then
		echo "Info dhcp.lan.ignore: "$dhcp_ignore
		if [ "$dhcp_ignore" = "1" ]; then
			echo "Agent --> Enable dhcp.lan, set leasetime=2m"
			uci set dhcp.lan.leasetime="2m"
			uci set dhcp.lan.ignore=""
			uci commit
			/etc/init.d/dnsmasq restart
		fi
	else
		if [ "$dhcp_leasetime" = "2m" ]; then
			echo "Set leasetime=3h for disable mesh, controller"
			uci set dhcp.lan.leasetime="3h"
			uci commit
			/etc/init.d/dnsmasq restart
		fi
	fi
fi

# AP-535: start vt_check_daemon.sh
VT_FILE='vt_check_daemon'
for i in $VT_FILE
do
	if [ -f /tmp/$i ]; then
		vt_pid=`cat /tmp/$i`
		kill -15 $vt_pid
	fi

	vt_file_sh="/etc/$i.sh"
	sh $vt_file_sh &
	echo $! > /tmp/$i
done

# AP-801: Improve module LED(cont)
killall -SIGINT led_manager

# AP-820: Improve parentald
is_parentald_enabled=$( uci get parental.global.enabled)
if [[ $is_parentald_enabled == "1" ]]; then
	killall -SIGUSR2 parentald
fi
