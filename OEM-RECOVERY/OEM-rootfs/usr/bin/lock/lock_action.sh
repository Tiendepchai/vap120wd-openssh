MIN_IP_STRING_LEN=7 #example 1.1.1.1
IPV4_REGEX="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
map_enable=$(wificonf -f /etc/mapd_cfg.txt get MapEnable)
dev_role=$(wificonf -f /etc/mapd_cfg.txt get DeviceRole)
lock_status=$(cof_cli read LockStatus)
CMD=$1
ARGS=$2 $3 $4
init_lock_firewall() {
	#Set ebtables rules
	ebtables -N vt_lock
	ebtables -N vt_lock_whitelist
	ebtables -P vt_lock_whitelist RETURN
	ebtables -D FORWARD -j vt_lock
	ebtables -D vt_lock -j vt_lock_whitelist
	ebtables -I FORWARD -j vt_lock
	ebtables -I vt_lock -j vt_lock_whitelist

	#Set iptables rules
	iptables -N vt_lock_forward
	iptables -N vt_lock_input
	iptables -N vt_lock_whitelist
	ip6tables -N vt_lock_input
	ip6tables -N vt_lock_forward
	iptables -D input_rule -j vt_lock_input
	iptables -D forwarding_rule -j vt_lock_forward
	ip6tables -D input_rule -j vt_lock_input
	ip6tables -D forwarding_rule -j vt_lock_forward
	iptables -I input_rule -j vt_lock_input
	iptables -I forwarding_rule -j vt_lock_forward
	ip6tables -I input_rule -j vt_lock_input
	ip6tables -I forwarding_rule -j vt_lock_forward
}

switch_acl_allow_ip() {
	switch vtacl allow_dip 0 $1 00011000 0
	switch vtacl allow_sip 1 $1 00011000 2
}

switch_acl_on() {

	#Allow DHCP, DNS
	switch vtacl allow_dport 2 68 00011000 4
	switch vtacl allow_dport 3 67 00011000 5
	switch vtacl allow_dport 4 53 00011000 6
	switch vtacl allow_sport 5 53 00011000 7

	#Allow 1905, ARP
	switch vtacl allow_ethertype 6 0x893a 00011000 8
	switch vtacl allow_ethertype 7 0x0806 00011000 9

	#Drop all other packets
	switch vtacl drop 8 all 00011000 10

	#Enable ACL on port 3,4
	switch acl enable 3 1
	switch acl enable 4 1
}

switch_acl_off() {
	switch acl enable 3 0
	switch acl enable 4 0
}

flush_lock_firewall() {
	#Set ebtables rules
	ebtables -F vt_lock
	#Set iptables rules
	iptables -F vt_lock_forward
	iptables -F vt_lock_input
	ip6tables -F vt_lock_forward
	ip6tables -F vt_lock_input

	#disable switch's acl rules
	switch_acl_off
}

start_lock_firewall() {
	init_lock_firewall
	flush_lock_firewall
	lock_status=$(cof_cli read LockStatus)
	if [ "$lock_status" = "1" ];then
	#do nslookup to get tms server's ip and put it into whitelist
		broker_url=$(uci get obuspa.mqtt.broker_address)
		broker_ip=$(nslookup $broker_url | grep -A 1 $broker_url | grep -E -o $IPV4_REGEX)
		if [[ ${#broker_ip} -ge $MIN_IP_STRING_LEN ]]; then
			for ip in $broker_ip
			do
				switch_acl_allow_ip $ip
				iptables -C vt_lock_whitelist -s $ip -j ACCEPT > /dev/null 2>&1
				if [[ "$?" -eq "1" ]]; then
					iptables -A vt_lock_whitelist -s $ip -j ACCEPT
					iptables -A vt_lock_whitelist -d $ip -j ACCEPT
				fi

				ebtables -L vt_lock_whitelist | grep "$ip" > /dev/null 2>&1
				if [[ "$?" -eq "1" ]]; then
					ebtables -A vt_lock_whitelist -p IPv4 --ip-source $ip -j ACCEPT
					ebtables -A vt_lock_whitelist -p IPv4 --ip-destination $ip -j ACCEPT
				fi
			done 
		else
			echo "Cannot get ip for $broker_url"
		fi

	#Set ebtables rules
		ebtables -A vt_lock -p IPv4 --ip-proto udp --ip-dport 68 -j ACCEPT 
		ebtables -A vt_lock -p IPv4 --ip-proto udp --ip-dport 67 -j ACCEPT 
		ebtables -A vt_lock -p IPv4 --ip-proto udp --ip-dport 53 -j ACCEPT 
		ebtables -A vt_lock -p IPv4 --ip-proto udp --ip-sport 53 -j ACCEPT 
		ebtables -A vt_lock -p IPv4 --ip-proto tcp --ip-dport 53 -j ACCEPT 
		ebtables -A vt_lock -p IPv4 --ip-proto tcp --ip-sport 53 -j ACCEPT 
		ebtables -A vt_lock -p IPv6 --ip6-proto udp --ip6-dport 547 -j ACCEPT 
		ebtables -A vt_lock -p IPv6 --ip6-proto udp --ip6-dport 547 -j ACCEPT 
		# ebtables -A vt_lock -p IPv6 --ip6-proto udp --ip6-sport 53 -j ACCEPT 
		# ebtables -A vt_lock -p IPv6 --ip6-proto udp --ip6-dport 53 -j ACCEPT 
		# ebtables -A vt_lock -p IPv6 --ip6-proto tcp --ip6-sport 53 -j ACCEPT 
		# ebtables -A vt_lock -p IPv6 --ip6-proto tcp --ip6-dport 53 -j ACCEPT 
		ebtables -A vt_lock -p 0x893a -j ACCEPT 
		ebtables -A vt_lock -p ARP -j ACCEPT 
		ebtables -A vt_lock -j vt_lock_whitelist 
		ebtables -A vt_lock -j DROP 

	#Set iptables rules
		iptables -A vt_lock_forward -p udp --dport 53 -j ACCEPT
		iptables -A vt_lock_forward -p udp --sport 53 -j ACCEPT
		iptables -A vt_lock_forward -p tcp --dport 53 -j ACCEPT
		iptables -A vt_lock_forward -p tcp --sport 53 -j ACCEPT
		iptables -A vt_lock_forward -j vt_lock_whitelist
		iptables -A vt_lock_forward -j DROP 

		# ip6tables -A vt_lock_forward -p udp --dport 53 -j ACCEPT
		# ip6tables -A vt_lock_forward -p udp --sport 53 -j ACCEPT
		# ip6tables -A vt_lock_forward -p tcp --dport 53 -j ACCEPT
		# ip6tables -A vt_lock_forward -p tcp --sport 53 -j ACCEPT
		ip6tables -A vt_lock_forward -j DROP

		iptables -A vt_lock_input -p tcp --dport 443 -j DROP
		ip6tables -A vt_lock_input -p tcp --dport 443 -j DROP
	#Enable ACL rules
		switch_acl_on
	fi
}

do_lock() {
	WAIT=$1
	cof_cli write LockStatus 1
	start_lock_firewall
	killall dns_parser
	/usr/bin/dns_parser -i br-lan &

	if [ "$map_enable" = "1" -a "$dev_role" = "2" ];then
		ln -sf /etc/lock_config/network /etc/config/network
#		sleep $WAIT && /etc/init.d/network reload &
	fi
	sh /usr/sbin/smartalert_action enable
}

do_unlock() {
	WAIT=$1
	cof_cli write LockStatus 0
	flush_lock_firewall
	killall dns_parser
	if [ "$map_enable" = "1" -a "$dev_role" = "2" ];then
		ln -sf /etc/nw_agent_config/network /etc/config/network
#		sleep $WAIT && /etc/init.d/network reload &
	fi
	sh /usr/sbin/smartalert_action disable
}

#start the command
$CMD $ARGS
