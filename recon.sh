#!/bin/bash
PING_SCAN_FILE="1_ping_nmap"
IPV4_HOST_LIST="2_ipv4_host_list.txt"
IPV4_HOST_LIST_MAC="3_ipv4_host_list_mac.txt"
IPV6_HOST_LIST="4_ipv6_host_list.txt"
IPV6_HOST_LIST_MAC="5_ipv6_host_list_mac.txt"
FULL_HOST_LIST="6_full_host_list.txt"
FULL_HOST_LIST_SOME_PORTS="7_ports_partial.txt"
FULL_HOST_LIST_ALL_PORTS="8_ports_full.txt"

if [ "$#" -lt 2 ]; then
    echo "[!] Usage $0 [subnet] [interface]"
    exit 1
fi

IPV4_ADDRESSES="$1"
INTERFACE="$2"

NMAP_OPTS="-T4 -e $INTERFACE"

if [ ! "$(whoami)" = "root" ]; then
    echo "[!] This script requires root privileges, exiting..."
    exit 1
fi

nplan -json model.json -fresh

if [ ! -e "$PING_SCAN_FILE.txt" ]|| [ ! -e "$PING_SCAN_FILE.xml" ]; then
    echo "[*] Running nmap ping scan..."
    nmap -sn "$NMAP_OPTS" "$IPV4_ADDRESSES" -oG "$PING_SCAN_FILE.txt" -oX "$PING_SCAN_FILE.xml"
else
    echo "[!] $PING_SCAN_FILE exists already, skipping ping scan..."
fi

nplan -json model.json -nmap "$PING_SCAN_FILE.xml"
nplan -export -drawio networkplan.drawio -json model.json

if [ ! -e "$IPV4_HOST_LIST" ]; then
    echo "[*] Processing nmap output..."
    grep -v Down "$PING_SCAN_FILE.txt" | sed '/^#/d' | cut -d $'\t' -f 1 | cut -d ' ' -f 2,3 > "$IPV4_HOST_LIST"
else
    echo "[!] $IPV4_HOST_LIST exists already, skipping nmap output processing..."
fi

if [ ! -e "$IPV4_HOST_LIST_MAC" ]; then
    echo "[*] Resolving IP addresses..."
    while read host; do
        ip="$(echo -n "$host" | cut -d ' ' -f 1)"
        domain="$(echo -n "$host" | cut -d ' ' -f 2)"
        arping_output="$(arping -f "$ip" -w 2)"
        if [ "$?" = "0" ]; then
            echo $(echo -n "$arping_output" | sed -e '3,4d;1d' | cut -d '[' -f 2 | cut -d ']' -f 1 | tr 'A-Z' 'a-z') "$ip" "$domain"
        else
            echo "ff:ff:ff:ff:ff:ff" "$ip" "$domain"
        fi
    done <"$IPV4_HOST_LIST" | sort >"$IPV4_HOST_LIST_MAC"
else
    echo "[!] $IPV4_HOST_LIST_MAC exists already, skipping IP resolve..."
fi

if [ ! -e "$IPV6_HOST_LIST" ]; then
    echo "[*] Running scan6..."
    scan6 -i "$INTERFACE" -L -e -P global > "$IPV6_HOST_LIST"
else
    echo "[!] $IPV6_HOST_LIST exists already, skipping scan6..."
fi

nplan -json model.json -scan6 "$IPV6_HOST_LIST"
nplan -export -drawio networkplan.drawio -json model.json

if [ ! -e "$IPV6_HOST_LIST_MAC" ]; then
    paste -d ' ' <(cut -f3 -d ' ' $IPV6_HOST_LIST) <(cut -f1 -d ' ' $IPV6_HOST_LIST) | sort > $IPV6_HOST_LIST_MAC
    echo "[*] Processing scan6 output..."
else
    echo "[!] $IPV6_HOST_LIST_MAC exists already, skipping output processing..."
fi

if [ ! -e "$FULL_HOST_LIST" ]; then
    join -a 1 3_ipv4_host_list_mac.txt 5_ipv6_host_list_mac.txt | awk '{ print $1 "\t" $2 "\t" "\t" $4 "\t" $3}' | sort -k 2,2 -k 3,3 -k 4,4 -k 5,5 -n -t . > "$FULL_HOST_LIST"
    echo "[*] Merging IPv4 and IPv6 information..."
else
    echo "[!] $FULL_HOST_LIST exists already, skipping output processing..."
fi


echo "[*] Running partial port scan..."
while read host; do
    ip="$(echo -n "$host" | cut -d $'\t' -f 2)"
    mkdir -p $ip
    filename="$ip/partial"
    if [ ! -e "$filename.txt" ]; then
        nmap -PN $NMAP_OPTS "$ip" -oN "$filename"_human.txt -oG "$filename.txt" -oX "$filename.xml" >&2
    else
        echo "[*] $filename.txt exists, skipping partial port scan" >&2
    fi
    nplan -json model.json -nmap "$filename.xml"
    nplan -export -drawio networkplan.drawio -json model.json
    ports="$(grep Ports $filename.txt | cut -d $'\t' -f 2 | cut -d ' ' -f 2-)"
    echo -e "$host\t$ports"
done <"$FULL_HOST_LIST" >"$FULL_HOST_LIST_SOME_PORTS"

nplan -export -drawio networkplan.drawio -json model.json

echo "[*] Running full port scan..."
while read host; do
    ip="$(echo -n "$host" | cut -d $'\t' -f 2)"
    mkdir -p $ip
    filename="$ip/full"
    if [ ! -e "$filename.txt" ]; then
        nmap -PN -p- -A $NMAP_OPTS "$ip" -oN "$filename"_human.txt -oG "$filename.txt" -oX "$filename.xml">&2
    else
        echo "[*] $filename.txt exists, skipping full port scan" >&2
    fi
    nplan -json model.json -nmap "$filename.xml"
    nplan -export -drawio networkplan.drawio -json model.json
    echo -e "$host\t$(grep Ports $filename.txt | cut -d $'\t' -f 2 | cut -d ' ' -f 2-)"
done <"$FULL_HOST_LIST" >"$FULL_HOST_LIST_ALL_PORTS"

nplan -export -drawio networkplan.drawio -json model.json
