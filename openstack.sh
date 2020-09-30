#!/bin/bash

[ -f ./log.sh ] && source ./log.sh

_IPV4_SUBNET_ID=''
_FLAVOR_ID=''

_RC_FILE='/var/lib/libvirt/qemu/ssd/.laoyun'
_PROJECT_ID='d6bbc17def0a4c6e8ebaebfd55d7ae11'
_IPV4_NETID='8870ed5d-7eca-4ce7-8a35-0f679a382deb'
_SECURITY_GROUP_ID='49630f30-df74-4c9d-a8c1-53ec58228c26'
_IMAGE_ID='70d0fb10-3e3a-415e-a116-b231f21a9271'
_POOL_NAME='cinder-sas'
_VOLUME_TYPE='ceph-ssd'
ARP_RECORD_FILE="/var/lib/libvirt/qemu/ssd/last/monitor_arp_data/monitor_arp_record.data"
if [ ! -f ${_RC_FILE} ]
then
    log error "user laoyun profile is not exist"
    echo -1
    return
fi
source $_RC_FILE &>/dev/null

build_uc_tmp_vm(){

	IPADDRESS=$1
	QOS_RATE=$2
	VOLUME_SIZE=$3
	CPU=$4
	MEM=$5
        vm_system_type=$6
        echo ${vm_system_type} | grep -i windows &>/dev/null
        if [ $? -ne 0 ]
        then
            _IMAGE_ID='22e17210-eb00-4c7c-b00c-5bd0d5052551'
        fi
	ip_exists=$(echo $IPADDRESS | grep "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$")
	if [ -z "${ip_exists}" ];then
                log error "give a error ip"
		echo -1
                return
	fi

	sub_name=$(echo $IPADDRESS | tr '.' ' ' | awk '{print $3}')_subnet
        if [ $? -ne 0 -o -z "${sub_name}" ]
        then 
            log error "genarate sub_name err , sub_name is [${sub_name}]"
            echo -1
            return
        fi

	_IPV4_SUBNET_ID=$(openstack subnet show ${sub_name} | grep -w id |awk '{print $4}' | head -n 1)
        if [ $? -ne 0 -o -z "${_IPV4_SUBNET_ID}" ]
        then 
            log error "get sub net id err"
            echo -1
            return
        fi

        vm_name=$(echo ${IPADDRESS} | tr '.' '_')

	#创建port
	port_id=$(openstack port create --project $_PROJECT_ID --network $_IPV4_NETID  --fixed-ip subnet=$_IPV4_SUBNET_ID,ip-address=$IPADDRESS --enable --security-group $_SECURITY_GROUP_ID --qos-policy  ${QOS_RATE}Mbps ${vm_name}  -c id |grep -w id |awk '{print $4}')
	if [ -z "${port_id}" ];then
                log error "create openstack port err"
		echo -1
                return
	fi
	log debug "PORT_ID:${port_id}"

	#创建vm
	instance_id=$(nova boot ${vm_name}  --flavor ${CPU}C${MEM}M --nic port-id=$port_id --block-device source=image,id=$_IMAGE_ID,dest=volume,size=$VOLUME_SIZE,bootindex=0,shutdown=remove |grep -w id |awk '{print $4}')
	if [ -z "${instance_id}" ];then
		openstack delete port $port_id
                log error "create openstack instance err"
		echo -1
                return
	fi
        log debug "openstack instance id is ${instance_id}"
        echo ${instance_id}
}

#
uc_tmp_vm_poweroff(){
        instance_id=$1
	nova stop $instance_id &>/dev/null
	if [ $? -ne 0 ]; then
                log error "nova stop ${instance_id} err"
		echo -1
	else
		echo 0
	fi
}

#
uc_tmp_vm_replace_system_file(){
	QCOW2_FILE=$1
        instance_id=$2

	volume_id=$(nova volume-attachments $instance_id |awk 'NR==4{print $8}')
	rbd  rm $_POOL_NAME/volume-$volume_id &>/dev/null
	rbd import $QCOW2_FILE $_POOL_NAME/volume-$volume_id &>/dev/null
	if [ $? -ne 0 ]; then
                log error "replace ceph storage err , volume id is ${volume_id}"
		echo -1
	else
		echo 0
	fi
}

uc_tmp_data_volume_create(){
        QCOW2_FILE=$1
        data_volume_size=$2
        instance_id=$3
        data_volume=${QCOW2_FILE##*/}
        data_volume=${data_volume%.*}

	data_volume_id=$(cinder create --volume-type ceph-ssd --name ${data_volume} ${data_volume_size} |grep "^| id" |awk '{print $4}')
	if [ -z "${data_volume_id}" ];then
		echo -1
                return
	fi

        sleep 20

        rbd rm $_POOL_NAME/volume-$data_volume_id &>/dev/null
	rbd import $QCOW2_FILE $_POOL_NAME/volume-$data_volume_id &>/dev/null
	if [ $? -ne 0 ]; then
                log error "replace data storage err , volume id is ${data_volume_id}"
		echo -1
                return
        fi

	nova volume-attach $instance_id $data_volume_id &>/dev/null
	if [ $? -ne 0 ]; then
		echo -1
	else
		echo 0
	fi
}

#
uc_tmp_vm_start(){
        instance_id=$1
	nova start $instance_id &>/dev/null
	if [ $? -ne 0 ]; then
                log error "start openstack vm err"
		echo -1
	else
		echo 0
	fi
}

uc_tmp_vm_check_arp_bind_relation(){
    instance_id=$1
    vm_ip=$2
    #bind_ip=$(openstack port list --server ${instance_id} | grep "117.50" | awk '{print $4}' | tr '_' '.' 2>/dev/null)
    #bind_mac=$(openstack port list --server ${instance_id} | grep "117.50" | awk '{print $6}' 2>/dev/null)
    bind_info_str=$(openstack port list --server ${instance_id} | grep "117.50" | awk '{print $4,$6}' 2>/dev/null)
    bind_ip=$(echo ${bind_info_str%% *} | tr '_' '.')
    bind_mac=$(echo ${bind_info_str##* })
    if [ -z "${instance_id}" ] || [ -z "${vm_ip}" ] || [ -z "${bind_ip}" ] || [ -z "${bind_mac}" ]
    then
        log error "this is null param in check vm instance id ${instance_id} ip ${vm_ip} and mac ${bind_mac}"
        echo -1
        return
    fi

    if [ ! -f ${ARP_RECORD_FILE} ]
    then
        log error "ly compute4 have not push arp-info file monitor_arp_record.data in /var/lib/libvirt/qemu/ssd/last/monitor_arp_data"
        echo -1
        return
    fi
    
    if [ "A${vm_ip}" != "A${bind_ip}" -o "A$(grep ${vm_ip} ${ARP_RECORD_FILE} | grep -i ${bind_mac} 2>/dev/null)" == "A" ]
    then
        log debug "check openstack vm ${instance_id} ip ${vm_ip} and mac ${bind_mac} is not match with them in ${ARP_RECORD_FILE}"
        echo -1
        return
    fi
    echo 0
}

#not use
uc_tmp_vm_check_listen_tcp(){
    IPADDRESS=$1
    nmap ${IPADDRESS} | egrep "^[0-9]+/tcp" &>/dev/null
    if [ $? -ne 0 ]; then
        log debug "check new openstack vm ${IPADDRESS} listen tcp fail"
        echo -1
        return
    fi
    echo 0
}

#
uc_tmp_vm_check_ping(){
        instance_id=$1
        IPADDRESS=$2
        timeout=$3
        [ ! -z "${timeout}" ] || timeout=600
        i=0
        while [ ${i} -lt ${timeout} ]
        do
	    ping $IPADDRESS -c 1 -W 1 &>/dev/null
	    if [ $? -eq 0 ]; then
                log debug "ping new openstack vm success"
	    	echo 0
                return
	    fi
            arp_check_ret=$(uc_tmp_vm_check_arp_bind_relation ${instance_id} ${IPADDRESS})
            if [ ${arp_check_ret} -eq 0 ]
            then
                log debug "vm ${instance_id} have firewall , can not ping , but arp info check correct"
	    	echo 0
                return
            fi
            let i=i+1
        done
        echo -1
}

# 0 is SHUTOFF , 1 is RUNNING , 2 is other
uc_tmp_vm_get_state(){
    instance_id=$1
    if [ -z "${instance_id}" ]
    then
        log error "give a null instance_id"
        echo -1
        return
    fi

    vm_state=$(nova show ${instance_id} | grep "^| status" | awk '{print $4}')
    if [ -z "${vm_state}" ]
    then
        log error "get vm ${instance_id} status error"
        echo -1
        return
    fi

    if [ "A${vm_state}" == "ASHUTOFF" ]
    then
        log debug "vm ${instance_id} is shutoff"
        echo 0
        return
    elif [ "A${vm_state}" == "AACTIVE" ]
    then
        log debug "vm ${instance_id} is active"
        echo 1
        return
    else
        log debug "vm ${instance_id} neither shutoff nor active"
        echo 2
        return
    fi
}

uc_tmp_wait_vm_shutoff(){
    instance_id=$1
    interval_sec=$2
    cycle_time=$3

    [ ! -z "${interval_sec}" ] && [ ! -z "$(echo ${interval_sec} | grep '^[[:digit:]]*$')" ] || interval_sec=20
    [ ! -z "${cycle_time}" ] && [ ! -z "$(echo ${cycle_time} | grep '^[[:digit:]]*$')" ] || cycle_time=20

    i=0
    if [ "A$(uc_tmp_vm_get_state ${instance_id})" != "A0" ]
    then
        while [ $i -lt ${cycle_time} ]
        do
            sleep ${interval_sec}

            if [ "A$(uc_tmp_vm_get_state ${instance_id})" == "A0" ]
            then
                log info "the vm ${instance_id} is shutoff"
                echo 0
                return
            fi
            log debug "the vm ${instance_id} is still active"
            let i=i+1
        done
    else
        log error "vm ${instance_id} on openstack first startup state is not normal"
        echo -1
        return
    fi

    if [ "A$(uc_tmp_vm_get_state ${instance_id})" != "A0" ]
    then
        log error "vm ${instance_id} still active after ${cycle_time}*${interval_sec} secs"
        echo -1
        return
    fi
    echo 0
}

uc_tmp_wait_vm_active(){
    instance_id=$1
    interval_sec=$2
    cycle_time=$3

    [ ! -z "${interval_sec}" ] && [ ! -z "$(echo ${interval_sec} | grep '^[[:digit:]]*$')" ] || interval_sec=20
    [ ! -z "${cycle_time}" ] && [ ! -z "$(echo ${cycle_time} | grep '^[[:digit:]]*$')" ] || cycle_time=20

    i=0
    if [ "A$(uc_tmp_vm_get_state ${instance_id})" != "A1" ]
    then
        while [ $i -lt ${cycle_time} ]
        do
            sleep ${interval_sec}

            if [ "A$(uc_tmp_vm_get_state ${instance_id})" == "A1" ]
            then
                log info "the vm ${instance_id} is active"
                echo 0
                return
            fi
            log debug "the vm ${instance_id} is still shutoff"
            let i=i+1
        done
    else
        log error "vm ${instance_id} on openstack startup state is not normal"
        echo -1
        return
    fi

    if [ "A$(uc_tmp_vm_get_state ${instance_id})" != "A1" ]
    then
        log error "vm ${instance_id} still shutoff after ${cycle_time}*${interval_sec} secs"
        echo -1
        return
    fi
    echo 0
}

uc_stop_and_wait_state_shutoff(){
        instance_id=$1
	nova stop $instance_id &>/dev/null
	if [ $? -ne 0 ]; then
            log error "nova stop ${instance_id} err"
            echo -1
            return
	fi
        wait_result=$(uc_tmp_wait_vm_shutoff $instance_id 20 15)
        if [ ${wait_result} -ne 0 ]
        then
            log error "after 300 secs , instance id ${instance_id} still running"
            echo -1
            return
        fi
        echo 0
}

uc_hard_reboot(){
    instance_id=$1
    nova reboot --hard ${instance_id} &>/dev/null
    if [ $? -ne 0 ]; then
        log error "nova reboot hard ${instance_id} err"
        echo -1
        return
    fi
    echo 0
}

uc_reattach_volumes(){
    instance_id=$1
    host_name=$2
    if [ -z "${instance_id}" ] || [ -z "${host_name}" ]
    then
        log error "if want reattach volume , need give instance_id and host_name two paramters"
        echo -1
        return
    fi
    for d in `cinder list | egrep "${host_name}_.-flat" | grep "available" | awk '{print $6}' | sort -n 2>/dev/null`
    do
        tmp_volume_id=`cinder list | grep ${d} | awk '{print $2}' 2>/dev/null`
        if [ -z "${tmp_volume_id}" ]
        then
            log error "find ${d} volume id error"
            echo -1
            return
        fi
        nova volume-attach ${instance_id} ${tmp_volume_id} &>/dev/null
        if [ $? -ne 0 ]
        then
            log error "${d} volume attach error"
            echo -1
            return
        fi
    done 
    sleep 20
    echo 0
}

#build_uc_tmp_vm  "117.50.118.11" 1 30 1 512
