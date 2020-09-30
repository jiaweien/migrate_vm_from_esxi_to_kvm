#!/bin/bash

host_ip=$1
host_pswd=$2
logpath="/var/lib/libvirt/qemu/ssd/migrate_log"
[ -d ${logpath} ] || mkdir -p ${logpath} &>/dev/null
logfile=${logpath}/$3.log

[ -f ./log.sh ] && source ./log.sh
[ -f ./esxi_and_virsh.sh ] && source ./esxi_and_virsh.sh
[ -f ./openstack.sh ] && source ./openstack.sh

local_top_path="/var/lib/libvirt/qemu/ssd"
too_many_disk_count="${local_top_path}/migrate_log/too_many_disk_err.list"
vm_name=$3
vm_cpu_num=$4
vm_mem_size=$5
vm_ip_addr=$6
vm_band_width=$7
vm_system_type=$8
vm_version=$9
shift 9
vm_arch=$1
vm_disk_num=$2
vm_sys_disk_size=$3
shift 3
if [ ! -z $(echo ${vm_disk_num} | grep '^[[:digit:]]*$') ]
then
    if [ ${vm_disk_num} -eq 2 ]
    then
        vm_data_disk_size=$1
        shift 1
    elif [ ${vm_disk_num} -eq 1 ]    
    then
        echo "" &> /dev/null
    elif [ ${vm_disk_num} -gt 2 -a ${vm_disk_num} -lt 8 ] #if vm disk is more than 8, error
    then
        for i in `seq 1 ${vm_disk_num}`
        do
            [ ${i} == 1 ] && vm_data_disk_size=${i} && shift 1 && continue
            vm_data_disk_size_${i}=$1
            shift 1
        done
    else
        echo ${host_ip} ${host_pswd} ${vm_name} ${vm_cpu_num} ${vm_mem_size} ${vm_ip_addr} ${vm_band_width} ${vm_system_type} ${vm_version} ${vm_arch} ${vm_disk_num} ${vm_sys_disk_size} ${vm_data_disk_size} >> ${too_many_disk_count}
        echo ${vm_name} >> ${local_top_path}/migrate_log/${host_ip}_err_migrate_list
        exit 1
    fi
fi
nbd_num=$1
vm_temp_path="${local_top_path}/${vm_name}"

log debug "======================begin ${vm_name} migrate======================"
if [ ! -z $(echo ${vm_disk_num} | grep '^[[:digit:]]*$') -a ${vm_disk_num} -le 2 ]
then
    log debug "paramters is:"
    log debug "\t\t[host_ip=$host_ip]"
    log debug "\t\t[host_pswd=$host_pswd]"
    log debug "\t\t[vm_name=$vm_name]"
    log debug "\t\t[vm_cpu_num=$vm_cpu_num]"
    log debug "\t\t[vm_mem_size=$vm_mem_size]"
    log debug "\t\t[vm_ip_addr=$vm_ip_addr]" 
    log debug "\t\t[vm_band_width=$vm_band_width]"
    log debug "\t\t[vm_system_type=$vm_system_type]"
    log debug "\t\t[vm_version=$vm_version]"
    log debug "\t\t[vm_arch=$vm_arch]"
    log debug "\t\t[vm_sys_disk_size=$vm_sys_disk_size]"
    log debug "\t\t[vm_data_disk_size=$vm_data_disk_size]"
    log debug "\t\t[nbd_num=$nbd_num]"
else
    log warn "${vm_name} ip ${vm_ip_addr} has ${vm_disk_num} disk , manually operate"
    echo ${host_ip} ${host_pswd} ${vm_name} ${vm_cpu_num} ${vm_mem_size} ${vm_ip_addr} ${vm_band_width} ${vm_system_type} ${vm_version} ${vm_arch} ${vm_disk_num} ${vm_sys_disk_size} ${vm_data_disk_size} >> ${too_many_disk_count}
    echo ${vm_name} >> ${local_top_path}/migrate_log/${host_ip}_err_migrate_list
    exit -1
fi

esxi_vm_status=1

esxi_vm_id=$(esxi_get_vmid ${vm_name})
if [ -z "${esxi_vm_id}" -o $? -ne 0 ]
then
    log error "get ${vm_name} on esxi id err"
    exit -1
fi

esxi_vm_disk_num=0
esxi_vm_disk_num=$(esxi_count_disk_num ${vm_name})
if [ $? -ne 0 ]
then
    log error "count ${vm_name} disks error"
    exit -1
elif [ ${esxi_vm_disk_num} -gt 2 ]
then
    log error "${vm_name} have ${esxi_vm_disk_num} disks, so cannot be migrate automatic"
    echo ${host_ip} ${host_pswd} ${vm_name} ${vm_cpu_num} ${vm_mem_size} ${vm_ip_addr} ${vm_band_width} ${vm_system_type} ${vm_version} ${vm_arch} ${vm_disk_num} ${vm_sys_disk_size} ${vm_data_disk_size} >> ${too_many_disk_count}
    echo ${vm_name} >> ${local_top_path}/migrate_log/${host_ip}_err_migrate_list
    exit -1
fi

esxi_vm_status=$(esxi_power_getstate ${esxi_vm_id})
if [ -z "${esxi_vm_status}" -o $? -ne 0 ]
then
    log error "get ${vm_name} on esxi id err"
    exit -1
fi

err_process(){
    echo ${vm_name} >> ${local_top_path}/migrate_log/${host_ip}_err_migrate_list
    vm_state=$(virsh domstate ${vm_name}-flat 2>/dev/null | head -n 1)
    if [ $? -eq 0 -a "A${vm_state}" == "Arunning" ]
    then
        virsh destroy ${vm_name}-flat &>/dev/null
    fi
    if [ ! -z "${vm_name}" ]
    then
        log error "cleanup ${local_top_path}/${vm_name}"
        cd ${local_top_path} && rm -rf ${vm_name} &>/dev/null
    fi
    log error "======================end ${vm_name} migrate======================"
    if [ "A${esxi_vm_status}" == "A1" ]
    then
        if [ $(esxi_power_on ${vm_name}) -ne 0 ]
        then
            log error "migrate ${vm_name} err , and reboot vm on esxi err"
            exit -1
        fi
    fi
}

if [ "A${esxi_vm_status}" != "A0" ]
then
    shutdown_ret=$(esxi_power_shutdown ${vm_name})
    if [ -z "${shutdown_ret}" -o ${shutdown_ret} -ne 0 ]
    then
        err_process
        exit -1
    fi
fi

wget_ret=$(wget_vm_disk_file_to_local ${local_top_path} ${vm_name} 8080)
if [ -z "${wget_ret}" -o "A${wget_ret}" != "A0" ] 
then
    err_process
    exit -1
fi

install_driver_ret=$(local_vm_install_driver ${vm_temp_path} ${vm_system_type} ${vm_version} ${vm_arch} ${nbd_num})
if [ -z "${install_driver_ret}" -o "${install_driver_ret}" -ne 0 ]
then
    err_process
    log error "install driver in ${vm_temp_path} err"
    exit -1
fi

openstack_instance_id=$(build_uc_tmp_vm ${vm_ip_addr} ${vm_band_width} ${vm_sys_disk_size} ${vm_cpu_num} ${vm_mem_size} ${vm_system_type})
if [ -z "${openstack_instance_id}" -o -z "$(echo ${openstack_instance_id} | egrep -i '^[0-9a-z]+\-[0-9a-z]+\-[0-9a-z]+\-[0-9a-z]+\-[0-9a-z]+$')" ]
then
    err_process
    log error "openstack build vm ${vm_ip_addr} err"
    exit -1
fi

wait_openstack_build_ret=$(uc_tmp_wait_vm_active ${openstack_instance_id} 20 20)
if [ -z "${wait_openstack_build_ret}" -o "${wait_openstack_build_ret}" -ne 0 ]
then
    uc_stop_and_wait_state_shutoff ${openstack_instance_id} &>/dev/null
    err_process
    log error "after 20*20 secs , ${openstack_instance_id} still not active"
    exit -1
fi

openstack_poweroff_ret=$(uc_tmp_vm_poweroff ${openstack_instance_id})
if [ -z "${openstack_poweroff_ret}" -o "${openstack_poweroff_ret}" -ne 0 ]
then
    uc_stop_and_wait_state_shutoff ${openstack_instance_id} &>/dev/null
    err_process
    log error "poweroff ${openstack_instance_id} on openstack err"
    exit -1
fi

wait_openstack_shutoff_ret=$(uc_tmp_wait_vm_shutoff ${openstack_instance_id} 10 20)
if [ -z "${wait_openstack_shutoff_ret}" -o "${wait_openstack_shutoff_ret}" -ne 0 ]
then
    uc_stop_and_wait_state_shutoff ${openstack_instance_id} &>/dev/null
    err_process
    log error "after 10*20 secs , ${openstack_instance_id} still active"
    exit -1
fi

openstack_replace_ret=$(uc_tmp_vm_replace_system_file "${vm_temp_path}/${vm_name}-flat.vmdk" ${openstack_instance_id})
if [ -z "${openstack_replace_ret}" -o "${openstack_replace_ret}" -ne 0 ]
then
    uc_stop_and_wait_state_shutoff ${openstack_instance_id} &>/dev/null
    err_process
    log error "replace ${vm_temp_path}/${vm_name}-flat.vmdk ${openstack_instance_id} system volume err"
    exit -1
fi

if [ ${vm_data_disk_size} -gt 0 ]
then
    openstack_replace_data_ret=$(uc_tmp_data_volume_create "${vm_temp_path}/${vm_name}_1-flat.vmdk" ${vm_data_disk_size} ${openstack_instance_id})
    if [ -z "${openstack_replace_data_ret}" -o "${openstack_replace_data_ret}" -ne 0 ]
    then
        uc_stop_and_wait_state_shutoff ${openstack_instance_id} &>/dev/null
        err_process
        log error "replace ${vm_temp_path}/${vm_name}_1-flat.vmdk ${openstack_instance_id} data volume err"
        exit -1
    fi
fi

sleep 60

openstack_replug_disk_ret=$(uc_reattach_volumes ${openstack_instance_id} ${vm_name})
if [ -z "${openstack_replug_disk_ret}" -o "${openstack_replug_disk_ret}" -ne 0 ]
then
    uc_stop_and_wait_state_shutoff ${openstack_instance_id} &>/dev/null
    err_process
    log error "retry hot plug volume on ${openstack_instance_id} error"
    exit -1
fi

openstack_start_ret=$(uc_tmp_vm_start ${openstack_instance_id})
if [ -z "${openstack_start_ret}" -o "${openstack_start_ret}" -ne 0 ]
then
    uc_stop_and_wait_state_shutoff ${openstack_instance_id} &>/dev/null
    err_process
    log error "start ${openstack_instance_id} on openstack err"
    exit -1
fi

wait_openstack_build_ret=$(uc_tmp_wait_vm_active ${openstack_instance_id} 20 20)
if [ -z "${wait_openstack_build_ret}" -o "${wait_openstack_build_ret}" -ne 0 ]
then
    uc_stop_and_wait_state_shutoff ${openstack_instance_id} &>/dev/null
    err_process
    log error "after 20*20 secs , ${openstack_instance_id} still not active"
    exit -1
fi

#openstack_hard_reboot_ret=$(uc_hard_reboot ${openstack_instance_id})
#if [ -z "${openstack_hard_reboot_ret}" -o "${openstack_hard_reboot_ret}" -ne 0 ]
#then
#    uc_stop_and_wait_state_shutoff ${openstack_instance_id} &>/dev/null
#    err_process
#    log error "hard reboot ${openstack_instance_id} err"
#    exit -1
#fi

openstack_ping_ret=$(uc_tmp_vm_check_ping ${openstack_instance_id} ${vm_ip_addr})
if [ -z "${openstack_ping_ret}" -o "${openstack_ping_ret}" -ne 0 ]
then
    uc_stop_and_wait_state_shutoff ${openstack_instance_id} &>/dev/null
    err_process
    log error "neither ping openstack new vm ${vm_ip_addr} nor through compare arp-info monitor_arp_record.data"
    exit -1
fi

if [ "A${esxi_vm_status}" == "A0" ]
then
    openstack_poweroff_ret=$(uc_tmp_vm_poweroff ${openstack_instance_id})
    if [ -z "${openstack_poweroff_ret}" -o "${openstack_poweroff_ret}" -ne 0 ]
    then
        log warn "poweroff ${openstack_instance_id} on openstack error, but this is completed migrate. so ignore this error"
    fi
fi

[ ! -z "${vm_name}" ] && [ -d ${local_top_path}/${vm_name} ] && rm -rf ${local_top_path}/${vm_name} &>/dev/null
echo ${vm_name} >> ${local_top_path}/migrate_log/${host_ip}_suc_migrate_list
log debug "======================end ${vm_name} migrate======================"
