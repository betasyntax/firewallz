#!/bin/sh
#Set default vars

IFCONFIG=`which ifconfig`
IPTABLES=`which iptables`
LSMOD=`which lsmod`
GREP=`which grep`
AWK=`which awk`
SED=`which sed`
CUT=`which cut`
SED=`which sed`
ROUTE=`which route`
DEPMOD=`which depmod`
INSMOD=`which insmod`
MODPROBE=`which modprobe`
RMMOD=`which rmmod`
PING=`which ping`
HOST=`which host`
UNIVERSE="0.0.0.0/0"
BROADCAST="255.255.255.255"

#next we are going to try and set these vars from the passed arguments




# while getopts hotin:hotip:cldin:cldip: option
# do
#  case "${option}"
#  in
#  hotin) HOTIN=${OPTARG};;
#  hotip) HOTIP=${OPTARG};;
#  cldin) CLDIN=${OPTARG};;
#  cldip) CLDIP=$OPTARG;;
#  esac
# done

# echo $HOTIN
# echo $HOTIP
# echo $CLDIN
# echo $CLDIP

# exit

HOTIN="enp4s0"
HOTIP="`$IFCONFIG $HOTIN | $GREP 'inet addr' | $AWK '{print $2}' | sed -e 's/.*://'`"
#HOTIP="`$IFCONFIG | $GREP P-t-P | $CUT -d ":" -f 2 | $CUT -d " " -f 1`"
CLDIN="enp6s0"
CLDIP="10.0.1.1"
CLDNET="10.0.1.0/24"
#WIFIIN="ath0"
#WIFIIP="192.168.12.1"
#WIFINET="192.168.12.0/24"
#VPNIN="tun+"
#VPNIP="192.168.200.1"
#VPNNET="192.168.200.0/24"
#VPN2IN="tap+"
#VPN2IP="10.0.1.1"
#VPN2NET="10.0.1.0/24"
FIREWALL="/etc/firewall.rules"
# BADMODULES="ip_fwadm ip_chains"
BADMODULES=""
#MODULES="tun ipt_state ipt_limit ipt_LOG sch_ingress cls_fw sch_sfq sch_htb ipt_length ipt_MARK ipt_tos iptable_mangle iptable_filter ipt_MASQUERADE iptable_nat ip_conntrack ip_tables"
MODULES="ip_tables"
TCPPORTS=""
#UDPPORTS="67 68"
#UDPPORTS="9500"
DOWNLINK=2900
UPLINK=1500
BURST=32
#TOS10TCPPORTS="22"
#TOS10TCPPORTS="53 80 443"
#TOS20TCPPORTS="22"
#TOS30TCPPORTS="21"
#TOS10UDPPORTS="1:"
#TOS20UDPPORTS=""
#TOS30UDPPORTS=""
declare -A FWHOST
NHOST=2
# Add your hosts here along with any tcp/udp ports.

FWHOST[ip1]="10.0.1.10"
FWHOST[tcp1]="8000"
FWHOST[udp1]=""
FWHOST[ip2]="10.0.1.200"
FWHOST[tcp2]="5222 9988 17502 20000:20100 22990 42127 25358:25360"
FWHOST[udp2]="3659 14000:14016 22990:23006 25200:25300 25358:25360"
# /bin/echo " Variables Set,"
prep() {
        if [ -n "$BADMODULES" ]; then
                /bin/echo "   Removing modules : "
                for BADMODULE in $BADMODULES; do
                        /bin/echo -en "$BADMODULE, "
                        if [ -z "` $LSMOD | $GREP $BADMODULE | $AWK {'print $1'} `" ]; then
                                $RMMOD $BADMODULE
                        fi
                done
        fi
        /bin/echo -n "Re-loading kernel modules: "
        if [ -n "$MODULES" ]; then
                for MODULE in $MODULES; do
                        /bin/echo -en "$MODULE "
                        if [ -z "` $LSMOD | $GREP $MODULE | $AWK {'print $1'} `" ]; then
                                $RMMOD $MODULE; $MODPROBE $MODULE
                        fi
                done
        fi
        /bin/echo " "
        tc qdisc del dev $HOTIN root    2> /dev/null > /dev/null
        tc qdisc del dev $HOTIN ingress 2> /dev/null > /dev/null
}
clean() {
        $IPTABLES -F INPUT
        $IPTABLES -P INPUT DROP
        $IPTABLES -F OUTPUT
        $IPTABLES -P OUTPUT DROP
        $IPTABLES -F FORWARD
        $IPTABLES -P FORWARD DROP
        $IPTABLES -t nat -F
        if [ -n "`$IPTABLES -L | $GREP drop-and-log-it`" ]; then
                $IPTABLES -F drop-and-log-it
        fi
        if [ -n "`$IPTABLES -L | $GREP luser-drop-and-log-it`" ]; then
                $IPTABLES -F luser-drop-and-log-it
        fi
        if [ -n "`$IPTABLES -L | $GREP base-policy`" ]; then
                $IPTABLES -F base-policy
        fi
        $IPTABLES -X
        $IPTABLES -Z
}
services() {
        if [ -n "$TCPPORTS" ]; then
                /bin/echo -en "Allowing in TCP ports: "
                for PORT in $TCPPORTS; do
                        /bin/echo -en "$PORT, "
                        $IPTABLES -A INPUT -i $HOTIN -d $HOTIP -p tcp --dport $PORT -j ACCEPT
                done
                /bin/echo " "
        fi
        if [ -n "$UDPPORTS" ]; then
                /bin/echo -en "Allowing in UDP ports: "
                for PORT in $UDPPORTS; do
                        /bin/echo -en "$PORT, "
                        $IPTABLES -A INPUT -i $HOTIN -d $HOTIP -p udp --dport $PORT -j ACCEPT
                done
                /bin/echo " "
        fi
        /bin/echo "Loading Forwarding Rules:"
        for ((i=1;i<=$NHOST;i++));
        do
                if [ ! "${FWHOST[tcp$i]}" == 0 ]; then
                        /bin/echo -en "forwarding TCP ports to ${FWHOST[ip$i]} : "
                        for PORT in ${FWHOST[tcp$i]}; do
                                /bin/echo -en "$PORT, "
                                $IPTABLES -t nat -A PREROUTING -p tcp --dport $PORT -i $HOTIN -j DNAT --to-destination ${FWHOST[ip$i]}
                                $IPTABLES -A FORWARD -p tcp --dport $PORT -i $HOTIN -o $CLDIN -d ${FWHOST[ip$i]} -j ACCEPT
                        done
                        /bin/echo " "
                fi
                if [ ! "${FWHOST[udp$i]}" == 0 ]; then
                        /bin/echo -en "forwarding UDP ports to ${FWHOST[ip$i]} : "
                        for PORT in ${FWHOST[udp$i]}; do
                                /bin/echo -en "$PORT, "
                                $IPTABLES -t nat -A PREROUTING -p udp --dport $PORT -i $HOTIN -j DNAT --to-destination ${FWHOST[ip$i]}
                                $IPTABLES -A FORWARD -p udp --dport $PORT -i $HOTIN -o $CLDIN -d ${FWHOST[ip$i]} -j ACCEPT
                        done
                        /bin/echo " "
                fi
        done
}
rules() {
        $IPTABLES -N drop-and-log-it
        $IPTABLES -A drop-and-log-it -j LOG --log-level info --log-prefix="DROP TRAFFIC: "
        $IPTABLES -A drop-and-log-it -j DROP
        $IPTABLES -N luser-drop-and-log-it
        $IPTABLES -A luser-drop-and-log-it -j LOG --log-level info --log-prefix="LUSER TRAFFIC: "
        $IPTABLES -A luser-drop-and-log-it -j DROP
        $IPTABLES -N base-policy
        $IPTABLES -F base-policy
        $IPTABLES -A base-policy -f -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -m state --state INVALID -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p ALL -s $UNIVERSE -d $BROADCAST -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --tcp-flags ALL FIN,URG,PSH -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --tcp-flags ALL ALL -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --tcp-flags ALL NONE -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --tcp-flags SYN,RST SYN,RST -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --tcp-flags SYN,FIN SYN,FIN -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 7 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p udp --dport 7 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 11 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 15 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 19 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p udp --dport 19 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 23 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 69 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 79 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 87 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 98 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 111 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 520 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 540 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 1080 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 1114 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 2000 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 10000 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 6000:6063 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p udp --dport 33434:33523 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 6670 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 1243 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p udp --dport 1243 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 6711:6713 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p udp --dport 6711:6713 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 27374 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p udp --dport 27374 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 12345:12346 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 20034 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p tcp --dport 31337:31338 -m limit --limit 6/minute -j luser-drop-and-log-it
        $IPTABLES -A base-policy -p udp --dport 28431 -m limit --limit 6/minute -j luser-drop-and-log-it
#       wifi
        # vpn
        $IPTABLES -A INPUT -i $HOTIN -j base-policy
        $IPTABLES -A INPUT -i lo -s $UNIVERSE -d $UNIVERSE -j ACCEPT
        $IPTABLES -A INPUT -i $HOTIN -s $CLDNET -d $UNIVERSE -j luser-drop-and-log-it
        $IPTABLES -A INPUT -i $HOTIN -p udp --dport 67 -s $UNIVERSE -j ACCEPT
        $IPTABLES -A INPUT -i $HOTIN -p udp --dport 68 -s $UNIVERSE -j DROP
        $IPTABLES -I INPUT -i $CLDIN -p udp --dport 67:68 --sport 67:68 -j ACCEPT
        $IPTABLES -A INPUT -i $CLDIN -s $CLDNET -d $UNIVERSE -j ACCEPT
        $IPTABLES -A INPUT -i $HOTIN -s $UNIVERSE -d $HOTIP -m state --state ESTABLISHED,RELATED -j ACCEPT
        services
        $IPTABLES -A INPUT -s $UNIVERSE -d $UNIVERSE -j drop-and-log-it
        $IPTABLES -A OUTPUT -o $HOTIN -j base-policy
        $IPTABLES -A OUTPUT -o lo -s $UNIVERSE -d $UNIVERSE -j ACCEPT
        $IPTABLES -A OUTPUT -o $HOTIN -p udp --dport 68 -j ACCEPT
        $IPTABLES -A OUTPUT -o $HOTIN -s $UNIVERSE -d $CLDNET -j luser-drop-and-log-it
        $IPTABLES -A OUTPUT -o $CLDIN -s $UNIVERSE -d $CLDNET -j ACCEPT
        $IPTABLES -A OUTPUT -o $HOTIN -s $HOTIP -d $UNIVERSE -j ACCEPT
        $IPTABLES -A OUTPUT -s $UNIVERSE -d $UNIVERSE -j drop-and-log-it
        $IPTABLES -A FORWARD -o $HOTIN -j base-policy
        $IPTABLES -A FORWARD -i $CLDIN -s $CLDNET -o $HOTIN -d $UNIVERSE -j ACCEPT
        $IPTABLES -A FORWARD -i $HOTIN -m state --state ESTABLISHED,RELATED -j ACCEPT
        $IPTABLES -t nat -A POSTROUTING -o $HOTIN -j MASQUERADE
        $IPTABLES -A FORWARD -j drop-and-log-it
}
shaper() {
        tc qdisc add dev $HOTIN root pfifo_fast
}
vpn() {
        $IPTABLES -A INPUT -i $VPNIN -j ACCEPT
        $IPTABLES -A OUTPUT -o $VPNIN -j ACCEPT
        $IPTABLES -A FORWARD -i $VPNIN -j ACCEPT
#        $IPTABLES -t nat -A POSTROUTING -o $VPNIN -j MASQUERADE
}
wifi() {
        $IPTABLES -A INPUT -i $WIFIIN -j ACCEPT
        $IPTABLES -A OUTPUT -o $WIFIIN -j ACCEPT
        $IPTABLES -A FORWARD -i $WIFIIN -o $HOTIN -j ACCEPT
        $IPTABLES -A FORWARD -i $WIFIIN -o $CLDIN -j ACCEPT
        $IPTABLES -t nat -A POSTROUTING -o $WIFIIN -j MASQUERADE
}
stop() {
        /bin/echo "0" > /proc/sys/net/ipv4/ip_forward
        for a in `cat /proc/net/ip_tables_names`; do
                $IPTABLES -F -t $a
                $IPTABLES -X -t $a
                if [ $a == nat ]; then
                        $IPTABLES -t nat -P PREROUTING ACCEPT
                        $IPTABLES -t nat -P POSTROUTING ACCEPT
                        $IPTABLES -t nat -P OUTPUT ACCEPT
                elif [ $a == mangle ]; then
                        $IPTABLES -t mangle -P PREROUTING ACCEPT
                        $IPTABLES -t mangle -P INPUT ACCEPT
                        $IPTABLES -t mangle -P FORWARD ACCEPT
                        $IPTABLES -t mangle -P OUTPUT ACCEPT
                        $IPTABLES -t mangle -P POSTROUTING ACCEPT
                elif [ $a == filter ]; then
                        $IPTABLES -t filter -P INPUT ACCEPT
                        $IPTABLES -t filter -P FORWARD ACCEPT
                        $IPTABLES -t filter -P OUTPUT ACCEPT
                fi
        done

	/bin/echo -n "Clearing Firewall Tables... "

        $IPTABLES -F
        $IPTABLES -t nat -F
        $IPTABLES -X
        $IPTABLES -P FORWARD ACCEPT
        $IPTABLES -P INPUT ACCEPT
        $IPTABLES -P OUTPUT ACCEPT

        /bin/echo " Done"
	/bin/echo -n "Clearing Qdiscs.."

        tc qdisc del dev $HOTIN root
        /bin/echo " Done"

}
start() {
        /bin/echo "1" > /proc/sys/net/ipv4/ip_dynaddr
        /bin/echo "0" > /proc/sys/net/ipv4/icmp_echo_ignore_all
        /bin/echo "0" > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts
        /bin/echo "0" > /proc/sys/net/ipv4/conf/all/accept_source_route
        /bin/echo "0" > /proc/sys/net/ipv4/conf/all/accept_redirects
        /bin/echo "1" > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses
        for i in /proc/sys/net/ipv4/conf/*; do
                /bin/echo "1" > $i/rp_filter
        done
        prep
        clean
        shaper
        rules
        /bin/echo "1" > /proc/sys/net/ipv4/ip_forward
}

if [ "$1" = "start" ]; then
        start
elif [ "$1" = "restart" ]; then
        stop
        start
elif [ "$1" = "stop" ]; then
        stop
elif [ "$1" = "status" ]; then
        /bin/echo "  External Interface:  $HOTIN"
        /bin/echo "  External IP       :  $HOTIP"
        /bin/echo "  Internal Interface:  $CLDIN"
        /bin/echo "  Internal IP       :  $CLDIP"
        /bin/echo "  Internal Network  :  $CLDNET"
        /bin/echo "  VPN-1 Interface:  $VPNIN"
        /bin/echo "  VPN-1 IP       :  $VPNIP"
        /bin/echo "  VPN-1 Network  :  $VPNNET"
        /bin/echo "  Classes           : "
        tc -s class ls dev $HOTIN
        /bin/echo "  Shaping           : "
        tc -s qdisc ls dev $HOTIN
        /bin/echo " "
        $IPTABLES -L -n -v --line-numbers
        /bin/echo " "
        $IPTABLES -t nat -L -n -v --line-numbers
        /bin/echo " "
        $IPTABLES -t mangle -L -n -v --line-numbers
elif [ "$1" = "panic" ]; then
        /bin/echo "0" > /proc/sys/net/ipv4/ip_forward
        clean
        $IPTABLES -A INPUT -i lo -j ACCEPT
        $IPTABLES -A OUTPUT -o lo -j ACCEPT
elif [ "$1" = "save" ]; then
        $IPTABLESSAVE -c > $FIREWALL
elif [ "$1" = "restore" ]; then
        $IPTABLESRESTORE < $FIREWALL
else
        /bin/echo "start      start with predefined rules"
        /bin/echo "stop       delete all rules and set all to accept"
        /bin/echo "panic      close all but lo dev"
        /bin/echo "save       will store settings in ${FIREWALL}"
        /bin/echo "restore    will restore settings from ${FIREWALL}"
        /bin/echo "status     show status"
fi