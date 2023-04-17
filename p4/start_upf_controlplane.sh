#!/bin/bash

# Runs the control plane for the P4 UPF
# Currently just monitors for new uplink entries to add corresponding downlink entries
# The P4 UPF dataplane, upon a new uplink packet, adds the following to registers:
#   - UE IP
#   - TEID
#   - ingress port
#   - Ethernet source and destination addresses of the S1U connection used
#   - eNB IP
#   - Targetted S1U IP of the dataplane
# The controlplane checks to see if the UE IP is new, and if it is adds a downlink entry
# If the IP is known, it checks to see if the data is new and modifies the existing downlink entry if so

REG_SIZE=16
JSON_PATH="../../build/BMv2/networks/upf/upf.json"
THRIFT_PORT="9092"

read_register() {
    ./send_command.py $JSON_PATH $THRIFT_PORT "register_read $1" | cut -d " " -f 2
}

table_modify() {
    ./send_command.py $JSON_PATH $THRIFT_PORT "table_modify $1"
}

table_add() {
    ./send_command.py $JSON_PATH $THRIFT_PORT "table_add $1" | tail --lines 1 | cut -d " " -f 7
}

ctrs=()
ips=()
teids=()
swports=()
s1u_das=()
s1u_sas=()
enb_ips=()
s1u_ips=()
handles=()
for (( q=0; q<$REG_SIZE; q++ )); do
    ctrs+=( 0 )
done

#ctr=$(read_register "ue_ips_r 0")
#echo $ctr

#handle=$(table_add "downlink NoAction 192.0.0.2 =>")
#echo $handle

while :; do
    for (( q=0; q<$REG_SIZE; q++ )); do
        ctr=$(read_register "ctrs_r $q")
        if [ $ctr != ${ctrs[$q]} ]; then
            echo "New UL entry recorded"
            ip_exist=0
            ip=$(read_register "ue_ips_r $q")
            teid=$(read_register "ue_teids_r $q")
            swport=$(read_register "swports_r $q")
            s1u_da=$(read_register "s1u_das_r $q")
            s1u_sa=$(read_register "s1u_sas_r $q")
            enb_ip=$(read_register "enb_ips_r $q")
            s1u_ip=$(read_register "s1u_ips_r $q")
            for r in ${!ips[@]}; do
                if [ $ip == ${ips[$r]} ]; then
                    ip_exist=1
                    if [[ $teid != ${teids[$r]} || $swport != ${swports[$r]} || $s1u_da != ${s1u_das[$r]} ||\
                          $s1u_sa != ${s1u_sas[$r]} || $enb_ip != ${enb_ips[$r]} || $s1u_ip != ${s1u_ips[$r]} ]]
                        then
                        echo "Updating existing DL entry for UE with IP $ip"
                        catch=$(table_modify "downlink dlentry_add ${handles[$r]} $swport $s1u_da $s1u_sa $enb_ip $s1u_ip $teid")
                    else
                        echo "Nothing to update"
                    fi
                fi
            done
            if [ $ip_exist == 0 ]; then
                echo "Adding new DL entry for UE with IP $ip"
                handle=$(table_add "downlink dlentry_add $ip => $swport $s1u_da $s1u_sa $enb_ip $s1u_ip $teid")
                ips+=( $ip )
                teids+=( $teid )
                swports+=( $swport )
                s1u_das+=( $s1u_da )
                s1u_sas+=( $s1u_sa )
                enb_ips+=( $enb_ip )
                s1u_ips+=( $s1u_ip )
                handles+=( $handle )
            fi
            ctrs[$q]=$ctr
        fi
    done
done
