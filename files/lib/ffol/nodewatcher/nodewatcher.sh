#!/bin/sh
# Netmon Nodewatcher (C) 2010-2012 Freifunk Oldenburg
# License; GPL v3

SCRIPT_VERSION="47"

#test -f /tmp/started || exit

#Get the configuration from the uci configuration file
#If it does not exists, then get it from a normal bash file with variables.
if [ -f /etc/config/nodewatcher ];then
    SCRIPT_ERROR_LEVEL=$(uci get nodewatcher.@script[0].error_level)
    SCRIPT_LOGFILE=$(uci get nodewatcher.@script[0].logfile)
    SCRIPT_DATA_FILE=$(uci get nodewatcher.@script[0].data_file)
    MESH_INTERFACE=$(uci get nodewatcher.@network[0].mesh_interface)
    IFACEBLACKLIST=$(uci get nodewatcher.@network[0].iface_blacklist)
    IPWHITELIST=$(uci get nodewatcher.@network[0].ip_whitelist)
    SCRIPT_STATUS_FILE=$(uci get nodewatcher.@script[0].status_text_file)
else
    . "$(dirname "$0")/nodewatcher_config"
fi

if [ "$SCRIPT_ERROR_LEVEL" -gt "1" ]; then
    err() {
        echo "$1" >> "$SCRIPT_LOGFILE"
    }
else
    err() {
        :
    }
fi

#This method checks if the log file has become too big and deletes the first X lines
delete_log() {
    if [ -f "$SCRIPT_LOGFILE" ]; then
        if [ "$(find "$SCRIPT_LOGFILE" -printf "%s")" -gt "6000" ]; then
            sed -i '1,60d' "$SCRIPT_LOGFILE"
            err "$(date): Logfile has been made smaller"
        fi
    fi
}

inArray() {
    local value
    for value in $1; do
        if [ "$value" = "$2" ]; then
            return 0
        fi
    done
    return 1
}

#This method generates the crawl data XML file that is being fetched by netmon
#and provided by a small local httpd
crawl() {
    #Get system data from other locations
    err "$(date): Collecting basic system status data"
    hostname="$(cat /proc/sys/kernel/hostname)"
    mac=$(awk '{ mac=toupper($1); gsub(":", "", mac); print mac }' /sys/class/net/br-mesh/address 2>/dev/null)
    [ "$hostname" = "LEDE" ] && hostname="$mac"
    [ "$hostname" = "FFF" ] && hostname="$mac"
    description="Gluon Node, no more Infos"
    if [ -n "$description" ]; then
        description="<description><![CDATA[$description]]></description>"
    fi
    latitude="$(uci -q get gluon-node-info.@location[0].latitude)"
    longitude="$(uci -q get gluon-node-info.@location[0].longitude)"
    if [ -n "$longitude" -a -n "$latitude" ]; then
        geo="<geo><lat>$latitude</lat><lng>$longitude</lng></geo>";
    fi
    position_comment="Gluon Node, no more Infos"
    if [ -n "$position_comment" ]; then
        position_comment="<position_comment><![CDATA[$position_comment]]></position_comment>"
    fi
    contact="$(uci -q get gluon-node-info.@owner[0].contact)"
    if [ -n "$contact" ]; then
        contact="<contact>$contact</contact>"
    fi
    uptime=$(awk '{ printf "<uptime>"$1"</uptime><idletime>"$2"</idletime>" }' /proc/uptime)

    memory=$(awk '
        /^MemTotal/ { printf "<memory_total>"$2"</memory_total>" }
        /^Cached:/ { printf "<memory_caching>"$2"</memory_caching>" }
        /^Buffers/ { printf "<memory_buffering>"$2"</memory_buffering>" }
        /^MemFree/ { printf "<memory_free>"$2"</memory_free>" }
    ' /proc/meminfo)
    cpu=$(awk -F': ' '
        /model/ { printf "<cpu>"$2"</cpu>" }
        /system type/ { printf "<chipset>"$2"</chipset>" }
        /platform/ { printf "<chipset>"$2"</chipset>" }
    ' /proc/cpuinfo)
    model="<model>$(cat /var/sysinfo/model)</model>"
    local_time="$(date +%s)"
    load=$(awk '{ printf "<loadavg>"$3"</loadavg><processes>"$4"</processes>" }' /proc/loadavg)

    err "$(date): Collecting version information"

    batman_adv_version=$(cat /sys/module/batman_adv/version)
    kernel_version=$(uname -r)
    if [ -x /usr/bin/fastd ]; then
        fastd_version="<fastd_version>$(/usr/bin/fastd -v | awk '{ print $2 }')</fastd_version>"
    fi
    nodewatcher_version=$SCRIPT_VERSION

    if [ -f "$SCRIPT_STATUS_FILE" ]; then
        status_text="<status_text>$(cat "$SCRIPT_STATUS_FILE")</status_text>"
    fi

    #Checks whether either fastd or L2TP is connected
    if pidof fastd >/dev/null || grep -q '1' /sys/class/net/l2tp*/carrier 2> /dev/null ; then
        vpn_active="<vpn_active>1</vpn_active>"
    else
        vpn_active="<vpn_active>0</vpn_active>"
    fi

    # example for /etc/openwrt_release:
    #DISTRIB_ID="OpenWrt"
    #DISTRIB_RELEASE="Attitude Adjustment"
    #DISTRIB_REVISION="r35298"
    #DISTRIB_CODENAME="attitude_adjustment"
    #DISTRIB_TARGET="atheros/generic"
    #DISTRIB_DESCRIPTION="OpenWrt Attitude Adjustment 12.09-rc1"
    . /etc/openwrt_release
    distname=$DISTRIB_ID
    distversion=$DISTRIB_RELEASE

    # example for /etc/firmware_release:
    #FIRMWARE_VERSION="95f36685e7b6cbf423f02cf5c7f1e785fd4ccdae-dirty"
    #BUILD_DATE="build date: Di 29. Jan 19:33:34 CET 2013"
    #OPENWRT_CORE_REVISION="35298"
    #OPENWRT_FEEDS_PACKAGES_REVISION="35298"
    #. /etc/firmware_release
    FIRMWARE_VERSION="20170918-137-gfc55f8e-dirty"
    FIRMWARE_COMMUNITY="franken"
    BUILD_DATE="build date: Fr 1. Dez 11:20:47 CET 2017"
    OPENWRT_CORE_REVISION="444add156f2a6d92fc15005c5ade2208a978966c"
    OPENWRT_FEEDS_PACKAGES_REVISION="cd5c448758f30868770b9ebf8b656c1a4211a240"
    FIRMWARE_VERSION=$(cat /lib/gluon/gluon-version)                  
    echo $FIRMWARE_VERSION

    SYSTEM_DATA="<status>online</status>"
    SYSTEM_DATA=$SYSTEM_DATA"$status_text"
    SYSTEM_DATA=$SYSTEM_DATA"<hostname>$hostname</hostname>"
    SYSTEM_DATA=$SYSTEM_DATA"${description}"
    SYSTEM_DATA=$SYSTEM_DATA"${geo}"
    SYSTEM_DATA=$SYSTEM_DATA"${position_comment}"
    SYSTEM_DATA=$SYSTEM_DATA"${contact}"
    if [ "$(uci -q get "system.@system[0].hood")" ]
    then
        SYSTEM_DATA=$SYSTEM_DATA"<hood>$(uci -q get "system.@system[0].hood")</hood>"
    fi
    SYSTEM_DATA=$SYSTEM_DATA"<hood>unterfuerberg</hood>"
    SYSTEM_DATA=$SYSTEM_DATA"<distname>Gluon $distname</distname>"
    SYSTEM_DATA=$SYSTEM_DATA"<distversion>$distversion</distversion>"
    SYSTEM_DATA=$SYSTEM_DATA"$cpu"
    SYSTEM_DATA=$SYSTEM_DATA"$model"
    SYSTEM_DATA=$SYSTEM_DATA"$memory"
    SYSTEM_DATA=$SYSTEM_DATA"$load"
    SYSTEM_DATA=$SYSTEM_DATA"$uptime"
    SYSTEM_DATA=$SYSTEM_DATA"<local_time>$local_time</local_time>"
    SYSTEM_DATA=$SYSTEM_DATA"<batman_advanced_version>$batman_adv_version</batman_advanced_version>"
    SYSTEM_DATA=$SYSTEM_DATA"<kernel_version>$kernel_version</kernel_version>"
    SYSTEM_DATA=$SYSTEM_DATA"$fastd_version"
    SYSTEM_DATA=$SYSTEM_DATA"<nodewatcher_version>$nodewatcher_version</nodewatcher_version>"
    SYSTEM_DATA=$SYSTEM_DATA"<firmware_version>$FIRMWARE_VERSION</firmware_version>"
    SYSTEM_DATA=$SYSTEM_DATA"<firmware_community>$FIRMWARE_COMMUNITY</firmware_community>"
    SYSTEM_DATA=$SYSTEM_DATA"<firmware_revision>$BUILD_DATE</firmware_revision>"
    SYSTEM_DATA=$SYSTEM_DATA"<openwrt_core_revision>$OPENWRT_CORE_REVISION</openwrt_core_revision>"
    SYSTEM_DATA=$SYSTEM_DATA"<openwrt_feeds_packages_revision>$OPENWRT_FEEDS_PACKAGES_REVISION</openwrt_feeds_packages_revision>"
    SYSTEM_DATA=$SYSTEM_DATA"$vpn_active"

    err "$(date): Collecting information from network interfaces"

    #Get interfaces
    interface_data=""
    #Loop interfaces
    #for entry in $IFACES; do
    for filename in $(grep 'up\|unknown' /sys/class/net/*/operstate); do
        ifpath=${filename%/operstate*}
        iface=${ifpath#/sys/class/net/}
        if inArray "$IFACEBLACKLIST" "$iface"; then
            continue
        fi

        #Get interface data for whitelisted interfaces
        # shellcheck disable=SC2016
        awkscript='
            /ether/ { printf "<mac_addr>"$2"</mac_addr>" }
            /mtu/ { printf "<mtu>"$5"</mtu>" }'
        if inArray "$IPWHITELIST" "$iface"; then
            # shellcheck disable=SC2016
            awkscript=$awkscript'
                /inet / { split($2, a, "/"); printf "<ipv4_addr>"a[1]"</ipv4_addr>" }
                /inet6/ && /scope global/ { printf "<ipv6_addr>"$2"</ipv6_addr>" }
                /inet6/ && /scope link/ { printf "<ipv6_link_local_addr>"$2"</ipv6_link_local_addr>"}'
        fi
        addrs=$(ip addr show dev "${iface}" | awk "$awkscript")

        traffic_rx=$(cat "$ifpath/statistics/rx_bytes")
        traffic_tx=$(cat "$ifpath/statistics/tx_bytes")

        interface_data=$interface_data"<$iface><name>$iface</name>$addrs<traffic_rx>$traffic_rx</traffic_rx><traffic_tx>$traffic_tx</traffic_tx>"

        interface_data=$interface_data$(iwconfig "${iface}" 2>/dev/null | awk -F':' '
            /Mode/{ split($2, m, " "); printf "<wlan_mode>"m[1]"</wlan_mode>" }
            /Cell/{ split($0, c, " "); printf "<wlan_bssid>"c[5]"</wlan_bssid>" }
            /ESSID/ { split($0, e, "\""); printf "<wlan_essid>"e[2]"</wlan_essid>" }
            /Freq/{ split($3, f, " "); printf "<wlan_frequency>"f[1]f[2]"</wlan_frequency>" }
            /Tx-Power/{ split($0, p, "="); sub(/[[:space:]]*$/, "", p[2]); printf "<wlan_tx_power>"p[2]"</wlan_tx_power>" }
        ')

        interface_data=$interface_data$(iw dev "${iface}" info 2>/dev/null | awk '
            /ssid/{ split($0, s, " "); printf "<wlan_ssid>"s[2]"</wlan_ssid>" }
            /type/ { split($0, t, " "); printf "<wlan_type>"t[2]"</wlan_type>" }
            /channel/{ split($0, c, " "); printf "<wlan_channel>"c[2]"</wlan_channel>" }
            /width/{ split($0, w, ": "); sub(/ .*/, "", w[2]); printf "<wlan_width>"w[2]"</wlan_width>" }
        ')

        interface_data=$interface_data"</$iface>"
    done

    err "$(date): Collecting information from batman advanced and its interfaces"
    #B.A.T.M.A.N. advanced
    if [ -f /sys/module/batman_adv/version ]; then
        for iface in $(grep active /sys/class/net/*/batman_adv/iface_status); do
            status=${iface#*:}
            iface=${iface%/batman_adv/iface_status:active}
            iface=${iface#/sys/class/net/}
            BATMAN_ADV_INTERFACES=$BATMAN_ADV_INTERFACES"<$iface><name>$iface</name><status>$status</status></$iface>"
        done

        # Build a list of direct neighbors
        batman_adv_originators=$(awk \
            'BEGIN { FS=" "; i=0 } # set the delimiter to " "
            /O/ { next } # ignore lines with O (will remove second line)
            /B/ { next } # ignore line with B (will remove first line)
            {   sub("\\(", "", $0) # remove parentheses
                sub("\\)", "", $0)
                sub("\\[", "", $0)
                sub("\\]:", "", $0)
                sub("  ", " ", $0)
                o=$1".*"$1 # build a regex to find lines that contains the $1 (=originator) twice
                if ($0 ~ o) # filter for this regex (will remove entries without direct neighbor)
                {
                    printf "<originator_"i"><originator>"$1"</originator><link_quality>"$3"</link_quality><nexthop>"$4"</nexthop><last_seen>"$2"</last_seen><outgoing_interface>"$5"</outgoing_interface></originator_"i">"
                    i++
                }
            }' /sys/kernel/debug/batman_adv/bat0/originators)

        batman_adv_gateway_mode=$(batctl gw)

        batman_adv_gateway_list=$(awk \
            'BEGIN { FS=" "; i=0 }
            /B.A.T.M.A.N./ { next }
            /Gateway/ { next }
            /No gateways/ { next }
            {   sub("\\(", "", $0)
                sub("\\)", "", $0)
                sub("\\[ *", "", $0)
                sub("\\]:", "", $0)
                sub("=> ", "true ", $0)
                sub("   ", "false ", $0)
                printf "<gateway_"i"><selected>"$1"</selected><gateway>"$2"</gateway><link_quality>"$3"</link_quality><nexthop>"$4"</nexthop><outgoing_interface>"$5"</outgoing_interface><gw_class>"$6" "$7" "$8"</gw_class></gateway_"i">"
                i++
            }' /sys/kernel/debug/batman_adv/bat0/gateways)
    fi
    err "$(date): Collecting information about conected clients"
    #CLIENTS
    client_count=0
    #dataclient=""
    #CLIENT_INTERFACES=$(bridge link | awk '$2 !~/^bat/{ printf $2" " }')
    #for clientif in ${CLIENT_INTERFACES}; do
    #    local cc=$(bridge fdb show br "$MESH_INTERFACE" brport "$clientif" | grep -v self | grep -v permanent -c)
    #    client_count=$((client_count + cc))
    #    dataclient="$dataclient<$clientif>$cc</$clientif>" <-- we need this again?
    #done
    client_count=$(batctl tl | grep -v '.P' | grep -v MainIF | grep -v Client | wc -l)

    dataair=""
    w2dump="$(iw dev w2ap survey dump 2> /dev/null | sed '/Survey/,/\[in use\]/d')"
    if [ -n "$w2dump" ] ; then
        w2_ACT="$(ACTIVE=$(echo "$w2dump" | grep "active time:"); set ${ACTIVE:-0 0 0 0 0}; echo -e "${4}")"
        w2_BUS="$(BUSY=$(echo "$w2dump" | grep "busy time:"); set ${BUSY:-0 0 0 0 0}; echo -e "${4}")"
        dataair="$dataair<airtime2><active>$w2_ACT</active><busy>$w2_BUS</busy></airtime2>"
    fi
    w5dump="$(iw dev w5ap survey dump 2> /dev/null | sed '/Survey/,/\[in use\]/d')"
    if [ -n "$w5dump" ] ; then
        w5_ACT="$(ACTIVE=$(echo "$w5dump" | grep "active time:"); set ${ACTIVE:-0 0 0 0 0}; echo -e "${4}")"
        w5_BUS="$(BUSY=$(echo "$w5dump" | grep "busy time:"); set ${BUSY:-0 0 0 0 0}; echo -e "${4}")"
        dataair="$dataair<airtime5><active>$w5_ACT</active><busy>$w5_BUS</busy></airtime5>"
    fi

    err "$(date): Putting all information into a XML-File and save it at $SCRIPT_DATA_FILE"

    DATA="<?xml version='1.0' standalone='yes'?><data>"
    DATA=$DATA"<system_data>$SYSTEM_DATA</system_data>"
    DATA=$DATA"<interface_data>$interface_data</interface_data>"
    DATA=$DATA"<batman_adv_interfaces>$BATMAN_ADV_INTERFACES</batman_adv_interfaces>"
    DATA=$DATA"<batman_adv_originators>$batman_adv_originators</batman_adv_originators>"
    DATA=$DATA"<batman_adv_gateway_mode>$batman_adv_gateway_mode</batman_adv_gateway_mode>"
    DATA=$DATA"<batman_adv_gateway_list>$batman_adv_gateway_list</batman_adv_gateway_list>"
    DATA=$DATA"<client_count>$client_count</client_count>"
    DATA=$DATA"<clients>$dataclient</clients>"
    DATA=$DATA"$dataair"
    DATA=$DATA"</data>"

    #write data to xml file that provides the data on httpd
    SCRIPT_DATA_DIR=$(dirname "$SCRIPT_DATA_FILE")
    test -d "$SCRIPT_DATA_DIR" || mkdir -p "$SCRIPT_DATA_DIR"
    echo "$DATA" | gzip | tee "$SCRIPT_DATA_FILE" | alfred -s 64
    echo "$DATA"
}

LANG=C

#Prüft ob das logfile zu groß geworden ist
err "$(date): Check logfile"
delete_log

#Erzeugt die statusdaten
err "$(date): Generate actual status data"
crawl

exit 0
