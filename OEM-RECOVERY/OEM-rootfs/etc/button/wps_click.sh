#!/bin/sh
echo "gpio btn wps!"

# Check wps 2G, enable and configured
i=0
BssidNum=$(wificonf -f /etc/wireless/mt7615/mt7615.1.2G.dat get BssidNum)
EnableSSID=$(wificonf -f /etc/wireless/mt7615/mt7615.1.2G.dat get EnableSSID)
WscStatusConf=$(wificonf -f /etc/wireless/mt7615/mt7615.1.2G.dat get WscConfStatus)

while [ $i -le $BssidNum ]
do
	SSID=${EnableSSID:$(( $i * 2 )):1}
	WscStatus=${WscStatusConf:$(( $i * 2 )):1}
    if [ "$SSID" = "1" ] && [ "$WscStatus" = "2" ] ;
    then
        echo "[WPS] run at rax$i"
		iwpriv rax$i set WscConfMode=7
		iwpriv rax$i set WscMode=2
		iwpriv rax$i set WscGetConf=1
    fi
    i=$(( $i + 1 ))
done

# Check wps 5G, enable and configured
i=0
BssidNum=$(wificonf -f /etc/wireless/mt7615/mt7615.1.5G.dat get BssidNum)
EnableSSID=$(wificonf -f /etc/wireless/mt7615/mt7615.1.5G.dat get EnableSSID)
WscStatusConf=$(wificonf -f /etc/wireless/mt7615/mt7615.1.5G.dat get WscConfStatus)

while [ $i -le $BssidNum ]
do
	SSID=${EnableSSID:$(( $i * 2 )):1}
	WscStatus=${WscStatusConf:$(( $i * 2 )):1}
    if [ "$SSID" = "1" ] && [ "$WscStatus" = "2" ] ;
    then
        echo "[WPS] run at ra$i"
		iwpriv ra$i set WscConfMode=7
		iwpriv ra$i set WscMode=2
		iwpriv ra$i set WscGetConf=1
    fi
    i=$(( $i + 1 ))
done

# Check mesh enable for onboarding
MapEnable=$(wificonf -f /etc/mapd_cfg.txt get MapEnable)
if [ "$MapEnable" = "1" ]; then
	echo "[MESH] Onboarding via PBC"
	wappctrl ra0 wps_pbc
fi

# send SIGUSR1 to led_manager
killall -SIGUSR1 led_manager
