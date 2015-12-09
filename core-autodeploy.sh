#!/bin/bash

# Script for Control Center and Zenoss Core 5 / Zenoss Resource Manager 5 deployement
# Copyright (C) 2015 Jan Garaj - www.jangaraj.com / www.monitoringartist.com / www.zenoss5taster.com
version="2015-12-09"

# Analytics
starttimestamp=$(date +%s)
cid=$(md5sum <<< $(hostname) | awk -F - '{print $1}' | tr -d ' ')
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=123234ee2&t=pageview&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Start&el=Start&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null

# Variables
# Default resource requirements
cpus_min=4
rams_min=20 #GB
# Default filesystem requirements (RHEL 7 / CentOS 7)
maxusage=90 #% max disk usage
root_fs_min_size=30 #GB
root_fs_type="xfs"
root_fs_path="/"
docker_fs_min_size=30 #GB
docker_fs_type="xfs"
docker_fs_path="/var/lib/docker"
serviced_fs_min_size=30 #GB
serviced_fs_type="xfs"
serviced_fs_path="/opt/serviced/var"
servicedvolumes_fs_min_size=1 #GB
servicedvolumes_fs_type="btrfs"
servicedvolumes_fs_path="/opt/serviced/var/volumes"
servicedbackups_fs_min_size=1 #GB
servicedbackups_fs_type="xfs"
servicedbackups_fs_path="/opt/serviced/var/backups"
# Mount parameters for fstab
mount_parameters_btrfs="rw,noatime,nodatacow,skip_balance 0 0"
mount_parameters_xfs="defaults,noatime 0 0"
mount_parameters_ext4="defaults 0 0"
# Docker and Zenoss Settings
docker_version=1.8.2
g2k=1048576
user="ccuser"
retries_max=90
sleep_duration=10
install_doc="https://www.zenoss.com/resources/documentation?field_zsd_core_value_selective=Core&field_product_value_selective=All&field_version_sort_tid_selective=All"
install_doc_enterprise="https://www.zenoss.com/resources/documentation?field_zsd_core_value_selective=ZSD&field_product_value_selective=All&field_version_sort_tid_selective=All"
log_watch="journalctl -u serviced -f -a -n 0"
log_watch_last_line="journalctl -u serviced -a -n 1 | tail -n 1"
zenoss_package="zenoss-core-service"
zenoss_package_enterprise="zenoss-resmgr-service"
zenoss_installation="Zenoss Core 5"
zenoss_installation_enterprise="Zenoss Resource Manager 5"
zenoss_template="Zenoss.core"
zenoss_template_enterprise="Zenoss.resmgr"
zenoss_impact=""
zenoss_impact_enterprise="zenoss/impact_5.0:5.0.3.0.0"
docker_registry_user=""
docker_registry_email=""
docker_registry_password=""
MHOST=""
advert="Ultimate graph and dashboard solution for Zenoss 5 / Grafana 2 for Zenoss 5 - http://beta.monitoringartist.com/grafana2-for-zenoss5.php"

# Magical colors of the wind
green='\e[0;32m'
yellow='\e[0;33m'
red='\e[0;31m'
blue='\e[0;34m'
endColor='\e[0m'

prompt_continue () {
    read answer
    if echo "$answer" | grep -iq "^y" ;then
        #echo " ... continuing"
        mycontinue="yes"
    else
        exit 1
    fi
}

check_filesystem() {
    mycontinue="no"
    mylocation=$1
    myfilesystem=$2
    myminsize=$3

    echo -en "${yellow} $mylocation filesystem check in progress...${endColor} "
    fs=$(df -TP | grep "$mylocation$" | awk '{print $2}')
    # Fall back to root fs
    if [ "$fs" == "" ]; then
        fs=$(df -TP | grep "/$" | awk '{print $2}')
    fi
    if [ "$fs" != "$myfilesystem" ]; then
        echo -en "\n${red} ${fs} ${mylocation} filesystem detected, but ${myfilesystem} is required. Do you want to continue (y/n)? ${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Wrong%20FS%20${mylocation}%20${fs}&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        prompt_continue
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Wrong%20FS%20${mylocation}%20${fs}%20yes&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        mycontinue="yes"
    fi
    usage=$(df -ha | grep "$mylocation$" | awk '{print $5}' | tail -n 1 | tr -d "%")
    # Fall back to root fs
    if [ "$usage" == "" ]; then
        usage=$(df -ha | grep "/$" | awk '{print $5}' | tail -n 1 | tr -d "%")
    fi
    if [ $usage -gt $maxusage ]; then
        echo -en "\n${red} ${mylocation} filesystem usage (${usage}%) is more than defined maximum ${maxusage}%. Do you want to continue (y/n)? ${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Overutilized%20FS%20${mylocation}&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        prompt_continue
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Overutilized%20FS%20${mylocation}%20yes&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        mycontinue="yes"
    fi
    ss=$(df -TP | grep "$mylocation$" | awk '{print $3}')
    # Fall back to root disk space
    if [ "$ss" == "" ]; then
        ss=$(df -TP | grep "/$" | awk '{print $3}')
    fi
    mss=$(($myminsize * $g2k))
    if [ $ss -lt $mss ]; then
        echo -en "\n${red} ${mylocation} filesystem size is less ($((ss/1024/1024))GB) than required ${myminsize}GB. Do you want to continue (y/n)? ${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Underutilized%20FS%20${mylocation}&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        prompt_continue
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Underutilized%20FS%20${mylocation}%20yes&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        mycontinue="yes"
    else
        if [ "$mycontinue" == "no" ]; then
            echo -e "${green}OK${endColor}"
        fi
    fi
}

echo -e "${yellow}Autodeploy script ${version} for Control Center master host and Zenoss Core 5/Zenoss Resource Manager 5${endColor}"
echo -e "${yellow}${advert}${endColor}"
echo -e "Install guide: ${install_doc}"
echo -en "${yellow}You should to read 'How to install Zenoss 5 successfuly' first - http://bit.ly/zenoss5. OK (y/n)? ${endColor}"
prompt_continue

# Check distro compatibility
notsupported="${red}Not supported OS version. Only RedHat 7, CentOS 7 and Ubuntu 14.04 are supported by Zenoss at the moment.${endColor}"
hostos="unknown"
# Check for Redhat/CentOS
if [ -f /etc/redhat-release ]; then
    #elv=`cat /etc/redhat-release | gawk 'BEGIN {FS="release "} {print $2}' | gawk 'BEGIN {FS="."} {print $1}'`
    cat /etc/redhat-release | grep 7
    if [ $? -ne 0 ]; then
        echo -e $notsupported
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Unsupported%20RHEL&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        exit 1
    fi
    hostos="redhat"
# Check for Ubuntu
elif grep -q "Ubuntu" /etc/issue; then
    if ! grep -q "14.04" /etc/issue; then
        echo -e $notsupported
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Unsupported%20Ubuntu&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        exit 1
    fi
    hostos="ubuntu"
    # ubuntu filesystem requirements
    root_fs_type="ext4"
    root_fs_min_size=60 #GB
    docker_fs_type="ext4"
    serviced_fs_type="ext4"
    servicedbackups_fs_type="ext4"
    log_watch="tailf /var/log/upstart/serviced.log"
    log_watch_last_line="tail -n2 /var/log/upstart/serviced.log 2>/dev/null"
    # Pre-install btrfs-tools
    echo -e "${yellow}Pre-installing btrfs-tools${endColor}"
    echo 'apt-get install -y btrfs-tools'
    apt-get install -y btrfs-tools
else
    # Not Supported
    echo -e $notsupported
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Unsupported%20OS&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    exit 1
fi

echo -e "${yellow}Hardware Requirements:${endColor}
Min number of available CPUs: ${cpus_min}
Min size of available RAM:    ${rams_min}GB
These filesystems must be mounted with correct type and size:
Path                        Type	Min size
${root_fs_path}                           ${root_fs_type}		${root_fs_min_size}GB
${docker_fs_path}             ${docker_fs_type}		${docker_fs_min_size}GB
${serviced_fs_path}           ${serviced_fs_type}		${serviced_fs_min_size}GB
${servicedvolumes_fs_path}   ${servicedvolumes_fs_type}	${servicedvolumes_fs_min_size}GB
${servicedbackups_fs_path}   ${servicedbackups_fs_type}		${servicedbackups_fs_min_size}GB"

# lang check, only en_GB.UTF-8/en_US.UTF-8 are supported
languages=$(locale | awk -F'=' '{print $2}' | tr -d '"' | grep -v '^$' | sort | uniq | tr -d '\r' | tr -d '\n')
if [ "$languages" != "en_GB.UTF-8" ] && [ "$languages" != "en_US.UTF-8" ]; then
    echo -en "${yellow}Warning: some non US/GB English or non UTF-8 locales are detected (see output from the command locale).\nOnly en_GB.UTF-8/en_US.UTF-8 are supported in core-autodeploy.sh script.\nYou can try to continue. Do you want to continue (y/n)? ${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Locales%20warning&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    prompt_continue
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Locales%20warning%20yes&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
fi

while getopts "i:r:u:e:p:h:d:s:v:b:x:" arg; do
  case $arg in
    i)
      # -i impact: pull impact image
      zenoss_impact=$zenoss_impact_enterprise
      ;;
    r)
      # -r resmgr: install enterprise/commercial Zenoss version
      zenoss_package=$zenoss_package_enterprise
      zenoss_installation=$zenoss_installation_enterprise
      zenoss_template=$zenoss_template_enterprise
      install_doc=$install_doc_enterprise
      curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=StartResmgr&el=OK&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
      ;;
    u)
      # -u <docker registry username>
      docker_registry_user=$OPTARG
      ;;
    e)
      # -e <docker registry email>
      docker_registry_email=$OPTARG
      ;;
    p)
      # -p <docker registry password>
      docker_registry_password=$OPTARG
      ;;
    h)
      # -h <IP of CC master>
      MHOST=$OPTARG
      ;;
    d)
      path=$docker_fs_path
      rfs=$docker_fs_type
      dev=$OPTARG
      echo -e "${yellow}0 Preparing ${path} filesystem - device: ${dev}${endColor}"
      fs=$(df -TP | grep ' \/var\/lib\/docker$' | awk '{print $2}')
      if [ ! -z "$fs" ]; then
          echo -e "${path} filesystem is already mounted, skipping creating this filesystem"
      else
          # mount point
          if [ ! -d $path ]; then
              echo "mkdir -p ${path}"
              mkdir -p ${path}
              if [ $? -ne 0 ]; then
                  echo -e "${red}Problem with creating mountpoint ${path}${endColor}"
                  curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Mountpoint%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
                  exit 1
              fi
          fi
          # mkfs
          echo -en "${dev} will be formated to ${rfs}. All current data on ${dev} will be lost and /etc/fstab will be updated. Do you want to continue (y/n)? "
          prompt_continue
          if [ "${rfs}" == "btrfs" ]; then
              echo "mkfs -t ${rfs} -f --nodiscard ${dev}"
              mkfs -t ${rfs} -f --nodiscard ${dev}
              mount_parameters=$mount_parameters_btrfs
          elif [ "${rfs}" == "ext4" ]; then
              echo "mkfs -t ${rfs} ${dev}"
              mkfs -t ${rfs} ${dev}
              mount_parameters=$mount_parameters_ext4
          else
              echo "mkfs -t ${rfs} -f ${dev}"
              mkfs -t ${rfs} -f ${dev}
              mount_parameters=$mount_parameters_xfs
          fi
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with formating ${dev}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Formating%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
          # fstab
          echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
          sed -i -e "\|^$dev|d" /etc/fstab
          echo "echo \"${dev} ${path} ${rfs} ${mount_parameters}\" >> /etc/fstab"
          echo "${dev} ${path} ${rfs} ${mount_parameters}" >> /etc/fstab
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with updating /etc/fstab for ${dev}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Fstab%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
          # mount
          echo "mount ${path}"
          mount ${path}
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with mounting ${path}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Mount%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
      fi
      ;;
    s)
      path="/opt/serviced/var"
      rfs=$serviced_fs_type
      dev=$OPTARG
      echo -e "${yellow}0 Preparing ${path} filesystem - device: ${dev}${endColor}"
      fs=$(df -TP | grep ' \/opt\/serviced\/var$' | awk '{print $2}')
      if [ ! -z "$fs" ]; then
          echo -e "${path} filesystem is already mounted, skipping creating this filesystem"
      else
          # mount point
          if [ ! -d $path ]; then
              echo "mkdir -p ${path}"
              mkdir -p ${path}
              if [ $? -ne 0 ]; then
                  echo -e "${red}Problem with creating mountpoint ${path}${endColor}"
                  curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Mountpoint%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
                  exit 1
              fi
          fi
          # mkfs
          echo -en "${dev} will be formated to ${rfs}. All current data on ${dev} will be lost and /etc/fstab will be updated. Do you want to continue (y/n)? "
          prompt_continue
          if [ "${rfs}" == "btrfs" ]; then
              echo "mkfs -t ${rfs} -f --nodiscard ${dev}"
              mkfs -t ${rfs} -f --nodiscard ${dev}
              mount_parameters=$mount_parameters_btrfs
          elif [ "${rfs}" == "ext4" ]; then
              echo "mkfs -t ${rfs} ${dev}"
              mkfs -t ${rfs} ${dev}
              mount_parameters=$mount_parameters_ext4
          else
              echo "mkfs -t ${rfs} -f ${dev}"
              mkfs -t ${rfs} -f ${dev}
              mount_parameters=$mount_parameters_xfs
          fi
          if [ $? -ne 0 ]; then
            echo -e "${red}Problem with formating ${dev}${endColor}"
            curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Formating%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
            exit 1
          fi
          # fstab
          echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
          sed -i -e "\|^$dev|d" /etc/fstab
          echo "echo \"${dev} ${path} ${rfs} ${mount_parameters}\" >> /etc/fstab"
          echo "${dev} ${path} ${rfs} ${mount_parameters}" >> /etc/fstab
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with updating /etc/fstab for ${dev}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Fstab%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
          # mount
          echo "mount ${path}"
          mount ${path}
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with mounting ${path}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Mount%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
      fi
      ;;
    v)
      path="/opt/serviced/var/volumes"
      rfs=$servicedvolumes_fs_type
      dev=$OPTARG
      echo -e "${yellow}0 Preparing ${path} filesystem - device: ${dev}${endColor}"
      fs=$(df -TP | grep ' \/opt\/serviced\/var\/volumes$' | awk '{print $2}')
      if [ ! -z "$fs" ]; then
          echo -e "${path} filesystem is already mounted, skipping creating this filesystem"
      else
          # mount point
          if [ ! -d $path ]; then
              echo "mkdir -p ${path}"
              mkdir -p ${path}
              if [ $? -ne 0 ]; then
                  echo -e "${red}Problem with creating mountpoint ${path}${endColor}"
                  curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Mountpoint%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
                  exit 1
              fi
          fi
          # mkfs
          echo -en "${dev} will be formated to ${rfs}. All current data on ${dev} will be lost and /etc/fstab will be updated. Do you want to continue (y/n)? "
          prompt_continue
          if [ "${rfs}" == "btrfs" ]; then
              echo "mkfs -t ${rfs} -f --nodiscard ${dev}"
              mkfs -t ${rfs} -f --nodiscard ${dev}
              mount_parameters=$mount_parameters_btrfs
          elif [ "${rfs}" == "ext4" ]; then
              echo "mkfs -t ${rfs} ${dev}"
              mkfs -t ${rfs} ${dev}
              mount_parameters=$mount_parameters_ext4
          else
              echo "mkfs -t ${rfs} -f ${dev}"
              mkfs -t ${rfs} -f ${dev}
              mount_parameters=$mount_parameters_xfs
          fi
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with formating ${dev}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Formating%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
          # fstab
          echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
          sed -i -e "\|^$dev|d" /etc/fstab
          echo "echo \"${dev} ${path} ${rfs} ${mount_parameters}\" >> /etc/fstab"
          echo "${dev} ${path} ${rfs} ${mount_parameters}" >> /etc/fstab
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with updating /etc/fstab for ${dev}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Fstab%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
          # mount
          echo "mount ${path}"
          mount ${path}
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with mounting ${path}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Mount%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
      fi
      ;;
    b)
      path="/opt/serviced/var/backups"
      rfs=$servicedbackups_fs_type
      dev=$OPTARG
      echo -e "${yellow}0 Preparing ${path} filesystem - device: ${dev}${endColor}"
      fs=$(df -TP | grep ' \/opt\/serviced\/var\/backups$' | awk '{print $2}')
      if [ ! -z "$fs" ]; then
          echo -e "${path} filesystem is already mounted, skipping creating this filesystem"
      else
          # mount point
          if [ ! -d $path ]; then
              echo "mkdir -p ${path}"
              mkdir -p ${path}
              if [ $? -ne 0 ]; then
                  echo -e "${red}Problem with creating mountpoint ${path}${endColor}"
                  curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Mountpoint%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
                  exit 1
              fi
          fi
          # mkfs
          echo -en "${dev} will be formated to ${rfs}. All current data on ${dev} will be lost and /etc/fstab will be updated. Do you want to continue (y/n)? "
          prompt_continue
          if [ "${rfs}" == "btrfs" ]; then
              echo "mkfs -t ${rfs} -f --nodiscard ${dev}"
              mkfs -t ${rfs} -f --nodiscard ${dev}
              mount_parameters=$mount_parameters_btrfs
          elif [ "${rfs}" == "ext4" ]; then
              echo "mkfs -t ${rfs} ${dev}"
              mkfs -t ${rfs} ${dev}
              mount_parameters=$mount_parameters_ext4
          else
              echo "mkfs -t ${rfs} -f ${dev}"
              mkfs -t ${rfs} -f ${dev}
              mount_parameters=$mount_parameters_xfs
          fi
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with formating ${dev}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Formating%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
          # fstab
          echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
          sed -i -e "\|^$dev|d" /etc/fstab
          echo "echo \"${dev} ${path} ${rfs} ${mount_parameters}\" >> /etc/fstab"
          echo "${dev} ${path} ${rfs} ${mount_parameters}" >> /etc/fstab
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with updating /etc/fstab for ${dev}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Fstab%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
          # mount
          echo "mount ${path}"
          mount ${path}
          if [ $? -ne 0 ]; then
              echo -e "${red}Problem with mounting ${path}${endColor}"
              curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Mount%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
              exit 1
          fi
      fi
      ;;
    x)
      # -x 'zabbix,influxdb,grafana,elasticsearch'
      EXTRA=",${OPTARG},"
      ;;
  esac
done

# Check for root access
echo -e "${blue}1 Checks - (`date -R`)${endColor}"
echo -e "${yellow}1.1 Root permission check${endColor}"
if [ "$EUID" -ne 0 ]; then
    echo -e "${red}Please run as root or use sudo${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

# Check for 64 bit arch
echo -e "${yellow}1.2 Architecture check${endColor}"
arch=$(uname -m)
if [ ! "$arch" = "x86_64" ]; then
  	echo -e "${red}Not supported architecture $arch. Architecture x86_64 only is supported.${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Unsupported%20architecture&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

# Check CPU requirements
echo -e "${yellow}1.4 CPU check${endColor}"
cpus=$(nproc)
if [ $cpus -lt $cpus_min ]; then
    echo -en "${red}Only ${cpus} CPUs have been detected, but at least $cpus_min are required. Do you want to continue (y/n)? ${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=CPU%20warning%20${cpus}&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    prompt_continue
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=CPU%20warning%20${cpus}%20yes&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
else
    echo -e "${green}Done${endColor}"
fi

# Check memory requirements
echo -e "${yellow}1.5 RAM check${endColor}"
rams=$(free -g | grep 'Mem' | awk '{print $2}')
if [ $rams -lt $rams_min ]; then
    echo -en "${red}Only ${rams}GB of RAM has been detected, but at least 20GB is recommended. Do you want to continue (y/n)? ${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=RAM%20warning%20${rams}GB&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    prompt_continue
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=RAM%20warning%20${rams}GB%20yes&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
fi
echo -e "${green}Done${endColor}"

# Check FS requirements
echo -e "${yellow}1.6 Filesystem configuration check${endColor}"
check_filesystem "/" "$root_fs_type" "$root_fs_min_size"
if [ "$hostos" == "redhat" ]; then
    check_filesystem "$docker_fs_path" "$docker_fs_type" "$docker_fs_min_size"
fi
check_filesystem "$serviced_fs_path" "$serviced_fs_type" "$serviced_fs_min_size"
check_filesystem "$servicedvolumes_fs_path" "$servicedvolumes_fs_type" "$servicedvolumes_fs_min_size"
check_filesystem "$servicedbackups_fs_path" "$servicedbackups_fs_type" "$servicedbackups_fs_min_size"


# Get IP information
echo -e "${blue}2 Preparing the host - (`date -R`)${endColor}"
# Define primary IP address
echo -e "${yellow}2.1 IP configurations${endColor}"
# ifconfig is not available in min installation - ip addr show used
is=$(ls /sys/class/net | grep -v ^lo | grep -v ^docker0 | grep -v ^veth)
no=$(echo ${is} | tr ' ' "\n" | wc -l)
if [ "$no" -gt "1" ]; then
    echo "Network interface auto detection failed. Available interfaces in your system:"
    echo $is
    echo "Please write interface, which you want to use for deployement (see listing above), e.g. eth1 or ens160:"
    read interface
    echo " ... continuing"
    privateipv4=$(ip addr show | grep -A 1 $interface | grep inet | awk '{print $2}' | awk -F'/' '{print $1}')
    if [ -z "$privateipv4" ]; then
        echo -e "${red}IPv4 address for selected interface ${interface} was not detected.${endColor}"
        exit 1
    fi
else
    echo "Detected interface: ${is}"
    privateipv4=$(ip addr show | grep -A 1 $is | grep inet | awk '{print $2}' | awk -F'/' '{print $1}')
fi

# AWS/HP Cloud public IPv4 address
publicipv4=$(curl --max-time 10 -s http://169.254.169.254/latest/meta-data/public-ipv4 | tr '\n' ' ')
if [[ ! $publicipv4 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    publicipv4=$privateipv4
fi

# Check and update host file
hostname=$(uname -n)
if [ "$hostname" == "localhost" ] || [ "$hostname" == "localhost.localdomain" ]; then
    hostname=$(echo $publicipv4 | tr '.' '-')
    hostname="ip-$hostname"
fi
# delete all hosts records 127.0. $hostname - ubuntu issue
sed -i -e "\|^127.0.*$hostname|d" /etc/hosts
echo "Hostname: $hostname"
grep "$privateipv4 $hostname" /etc/hosts
if [ $? -ne 0 ]; then
    echo "echo \"$privateipv4 $hostname\" >> /etc/hosts"
    echo "$privateipv4 $hostname" >> /etc/hosts
fi
echo "Public IPv4: $publicipv4"
echo "Private IPv4: $privateipv4"
echo -e "${green}Done${endColor}"

# Disable the firewall
echo -e "${yellow}2.2 Disable the firewall${endColor}"
if [ "$hostos" == "redhat" ]; then
    echo 'systemctl stop firewalld && systemctl disable firewalld'
    systemctl stop firewalld && systemctl disable firewalld
elif [ "$hostos" == "ubuntu" ]; then
    echo "ufw disable"
    ufw disable
fi
echo -e "${green}Done${endColor}"

# Enable persistent log storage
if [ "$hostos" == "redhat" ]; then
    echo -e "${yellow}2.3 Enable persistent storage for log files${endColor}"
    echo 'mkdir -p /var/log/journal && systemctl restart systemd-journald'
    mkdir -p /var/log/journal && systemctl restart systemd-journald
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with enabling persistent log storage${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=PerStorage%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        exit 1
    else
        echo -e "${green}Done${endColor}"
    fi
fi

# Disable SELinux
echo -e "${yellow}2.4 Disable selinux${endColor}"
test=$(test -f /etc/selinux/config && grep '^SELINUX=' /etc/selinux/config)
if [ ! -z "$test" ] && [ "$test" != "SELINUX=disabled" ]; then
    echo "echo 0 > /selinux/enforce"
    echo 0 > /selinux/enforce
    echo "sed -i.$(date +\"%j-%H%M%S\") -e 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config && grep '^SELINUX=' /etc/selinux/config"
    sed -i.$(date +"%j-%H%M%S") -e 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config && grep '^SELINUX=' /etc/selinux/config
    echo -e "${green}Done${endColor}"
else
    echo -e "${green}Done${endColor} - disabled already"
fi

# Setup software repositories
echo -e "${yellow}2.5 Zenoss/Docker repositories config${endColor}"
if [ "$hostos" == "redhat" ]; then
    echo 'rpm -ivh http://get.zenoss.io/yum/zenoss-repo-1-1.x86_64.rpm'
    output=$(rpm -ivh http://get.zenoss.io/yum/zenoss-repo-1-1.x86_64.rpm 2>&1)
    com_ret=$?
    echo "$output"
    substring="is already installed"
    if [ $com_ret -ne 0 ] && [ "$output" == "${output%$substring*}" ]; then
        echo -e "${red}Problem with installing Zenoss repository${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=InstallRepo%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        exit 1
    else
        yum clean all &>/dev/null
        echo -e "${green}Done${endColor}"
    fi
    # Docker repository
    echo '/etc/yum.repos.d/docker-main.repo'
    cat > /etc/yum.repos.d/docker-main.repo << EOF
[docker-main-repo]
name=Docker main Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF
    echo "yum -y -q install docker-engine-${docker_version}""
    yum -y -q install docker-engine-${docker_version}
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with Docker installation${endColor}"
        exit 1
    else
        echo -e "${green}Done${endColor}"
    fi
elif [ "$hostos" == "ubuntu" ]; then
    # Docker repository
    echo 'apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D'
    apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    echo 'curl -sO http://apt.dockerproject.org/repo/pool/main/d/docker-engine/docker-engine_${docker_version}-0~trusty_amd64.deb'
    curl -sO http://apt.dockerproject.org/repo/pool/main/d/docker-engine/docker-engine_${docker_version}-0~trusty_amd64.deb
    echo 'dpkg -i docker-engine_${docker_version}-0~trusty_amd64.deb'
    dpkg -i docker-engine_${docker_version}-0~trusty_amd64.deb
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with Docker installation${endColor}"
        exit 1
    else
        echo -e "${green}Done${endColor}"
    fi
    rm -rf docker-engine_${docker_version}-0~trusty_amd64.deb
    # Zenoss repository
    echo 'echo "deb [ arch=amd64 ] http://get.zenoss.io/apt/ubuntu trusty universe" > /etc/apt/sources.list.d/zenoss.list'
    echo "deb [ arch=amd64 ] http://get.zenoss.io/apt/ubuntu trusty universe" > /etc/apt/sources.list.d/zenoss.list
    apt-key adv --keyserver keys.gnupg.net --recv-keys AA5A1AD7
    # Make sure repos are updated or below packages fail.
    echo 'apt-get update'
    apt-get update
    echo 'sleep 5'
    sleep 5
    echo 'apt-get update'
    apt-get update
fi

# Install dnsmasq for docker
echo -e "${yellow}2.6 Install and start the dnsmasq package${endColor}"
if [ "$hostos" == "redhat" ]; then
    echo 'yum install -y dnsmasq && systemctl enable dnsmasq && systemctl start dnsmasq'
    yum install -y dnsmasq && systemctl enable dnsmasq && systemctl start dnsmasq
elif [ "$hostos" == "ubuntu" ]; then
    echo "apt-get install -y dnsmasq"
    apt-get install -y dnsmasq
fi
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with installing dnsmasq package${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=DnsmaqPkg%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    exit 1
else
    # Give dnsmasq a chance to startup
    if [ "$hostos" == "ubuntu" ]; then
        echo 'sleep 10'
        sleep 10
    fi
    echo -e "${green}Done${endColor}"
fi

# Install ntp for docker
echo -e "${yellow}2.7 Install and start the ntp package${endColor}"
if [ "$hostos" == "redhat" ]; then
    echo 'yum install -y ntp && systemctl enable ntpd'
    yum install -y ntp && systemctl enable ntpd
elif [ "$hostos" == "ubuntu" ]; then
    echo "apt-get install -y ntp"
    apt-get install -y ntp
fi
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with installing ntp package${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=NtpPkg%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

# Startup workaround for ntpd on redhat distributions
if [ "$hostos" == "redhat" ]; then
    echo -e "${yellow}2.8 ntpd autostart workaround${endColor}"
    echo 'echo "systemctl start ntpd" >> /etc/rc.d/rc.local && chmod +x /etc/rc.d/rc.local'
    sed -i -e "\|^systemctl start ntpd|d" /etc/rc.d/rc.local
    echo "systemctl start ntpd" >> /etc/rc.d/rc.local && chmod +x /etc/rc.d/rc.local
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with installing ntpd autostart workaround${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=NtpWorkaround%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        exit 1
    else
        echo -e "${green}Done${endColor}"
    fi
fi

# Start ntpd service
if [ "$hostos" == "redhat" ]; then
    echo -e "${yellow}2.9 ntpd start${endColor}"
    echo 'systemctl start ntpd'
    systemctl start ntpd
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with ntpd start${endColor}"
        exit 1
    else
        echo -e "${green}Done${endColor}"
    fi
fi

echo -e "${blue}3 Installing on the master host - (`date -R`)${endColor}"

# Install core services
echo -e "${yellow}3.1 Install Control Center, Zenoss Core/Resource Manager, and Docker${endColor}"
if [ "$hostos" == "redhat" ]; then
    echo "yum --enablerepo=zenoss-stable install -y ${zenoss_package}"
    yum --enablerepo=zenoss-stable install -y ${zenoss_package}
elif [ "$hostos" == "ubuntu" ]; then
    echo 'apt-get install -y --force-yes ${zenoss_package}'
    apt-get install -y --force-yes ${zenoss_package}
fi
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with installing Control Center, Zenoss Core and Docker${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}3.2 Start Docker${endColor}"

# Startup docker (not needed for Ubuntu)
if [ "$hostos" == "redhat" ]; then
    echo 'systemctl enable docker && systemctl start docker'
    systemctl enable docker && systemctl start docker
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with starting of Docker${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=DockerStart%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        exit 1
    else
        echo -e "${green}Done${endColor}"
    fi
fi

# Setup host for Zenoss Enterprise
if [ "$zenoss_package" == "$zenoss_package_enterprise" ] && [ -z "$MHOST" ]; then
    # docker login
    echo -e "${yellow}Authenticate to the Docker Hub repository${endColor}"
    mySetting=$HISTCONTROL; export HISTCONTROL=ignorespace
    myUser=$docker_registry_user
    myEmail=$docker_registry_email
    myPass=$docker_registry_password
    if [ "$hostos" == "redhat" ]; then
        # turn off history substitution using - problem with specific passwords
        set +H
        systemctl start docker
        sleep 10
        sh -c "docker login -u $myUser -e $myEmail -p '$myPass'"
        if [ $? -ne 0 ]; then
            echo -e "${red}Problem with authentication to the Docker Hub${endColor}"
            curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=DockerAuth%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
            exit 1
        fi
        export HISTCONTROL=$mySetting
    fi
    echo -e "${green}Done${endColor}"
fi

# Collect docker information
echo -e "${yellow}3.3 Identify the IPv4 address and subnet of Docker${endColor}"
echo "sleep 10"
sleep 10
echo "ip addr | grep -A 2 'docker0:' | grep inet | awk '{print \$2}' | awk -F'/' '{print \$1}'"
docker_ip=$(ip addr | grep -A 2 'docker0:' | grep inet | awk '{print $2}' | awk -F'/' '{print $1}')
if [ -z "$docker_ip" ]; then
    echo -e "${red}Problem with identifying IPv4 of Docker${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=DockerIPv4%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

# Configure docker settings
echo -e "${yellow}3.4 Add the devicemapper and DNS flags to the Docker startup options${endColor}"
if [ "$hostos" == "redhat" ]; then
    echo 'sed -i -e "\|^DOCKER_OPTS=\"-s devicemapper --dns=|d" /etc/sysconfig/docker'
    sed -i -e "\|^DOCKER_OPTS=\"-s devicemapper --dns=|d" /etc/sysconfig/docker
    echo 'echo "DOCKER_OPTS=\"-s devicemapper --dns=$docker_ip\"" >> /etc/sysconfig/docker'
    echo "DOCKER_OPTS=\"-s devicemapper --dns=$docker_ip\"" >> /etc/sysconfig/docker
elif [ "$hostos" == "ubuntu" ]; then
    echo 'sed -i -e "\|^DOCKER_OPTS=\"-s devicemapper --dns=|d" /etc/default/docker'
    sed -i -e "\|^DOCKER_OPTS=\"-s devicemapper --dns=|d" /etc/default/docker
    echo 'echo "DOCKER_OPTS=\"-s devicemapper --dns=$docker_ip\"" >> /etc/default/docker'
    echo "DOCKER_OPTS=\"-s devicemapper --dns=$docker_ip\"" >> /etc/default/docker
fi
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with adding devicemapper and DNS flags to the Docker${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=DockerFlags%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    exit 1
else
    echo -e "${green}Done${endColor}"
fi


# Setup administrator user for docker
echo -e "${yellow}3.5 Creating user ${user} for Control Center (serviced) management${endColor}"
echo "id -u ${user}"
id -u ${user}
if [ $? -ne 0 ]; then
    echo "adduser -M -c 'Management user for Control Center (serviced)' ${user}"
    useradd -M -c 'Management user for Control Center (serviced)' ${user}
    if [ "$hostos" == "redhat" ]; then
        echo "usermod -aG wheel ${user}"
        usermod -aG wheel ${user}
    elif [ "$hostos" == "ubuntu" ]; then
        echo "usermod -aG sudo ${user}"
        usermod -aG sudo ${user}
    fi
else
    echo 'User already exists'
fi
echo -e "${green}Done${endColor}"

# Restart docker services
echo -e "${yellow}3.6 Stop and restart Docker${endColor}"
if [ "$hostos" == "redhat" ]; then
    echo "systemctl stop docker && systemctl start docker"
    systemctl stop docker && systemctl start docker
elif [ "$hostos" == "ubuntu" ]; then
    echo "stop docker && start docker"
    stop docker && start docker
fi
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with restarting of Docker${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=DockerRestart%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

# Update serviced host configuration
if [ ! -z "$MHOST" ]; then
    echo -e "${yellow}Editing /etc/default/serviced on CC host${endColor}"
    EXT=$(date +"%j-%H%M%S")
    test ! -z "${MHOST}" && \
    sed -i.${EXT} -e 's|^#[^H]*\(HOME=/root\)|\1|' \
     -e 's|^#[^S]*\(SERVICED_REGISTRY=\).|\11|' \
     -e 's|^#[^S]*\(SERVICED_AGENT=\).|\11|' \
     -e 's|^#[^S]*\(SERVICED_MASTER=\).|\10|' \
     -e 's|^#[^S]*\(SERVICED_MASTER_IP=\).*|\1'${MHOST}'|' \
     -e '/=$SERVICED_MASTER_IP/ s|^#[^S]*||' \
     -e 's|\($SERVICED_MASTER_IP\)|'${MHOST}'|' \
     /etc/default/serviced
else
    # enable a multi-host deployment on the master
    echo -e "${yellow}Editing /etc/default/serviced on CC master${endColor}"
    EXT=$(date +"%j-%H%M%S")
    sed -i.${EXT} -e 's|^#[^H]*\(HOME=/root\)|\1|' \
     -e 's|^#[^S]*\(SERVICED_REGISTRY=\).|\11|' \
     -e 's|^#[^S]*\(SERVICED_AGENT=\).|\11|' \
     -e 's|^#[^S]*\(SERVICED_MASTER=\).|\11|' \
      /etc/default/serviced
fi

# Update serviced filesystem configuration
echo -e "${yellow}3.7 Change the volume type for application data${endColor}"
echo "sed -i.$(date +\"%j-%H%M%S\") -e 's|^#[^S]*\(SERVICED_FS_TYPE=\).*$|\1btrfs|' /etc/default/serviced"
sed -i.$(date +"%j-%H%M%S") -e 's|^#[^S]*\(SERVICED_FS_TYPE=\).*$|\1btrfs|' /etc/default/serviced
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with changing of volume type${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=ServicedConf%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

# rpcbind bug http://www.zenoss.org/forum/4726
if [ "$hostos" == "redhat" ]; then
    echo -e "${yellow}3.8 rpcbind workaround${endColor}"
    echo 'systemctl status rpcbind &>/dev/null'
    systemctl status rpcbind &>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${yellow}Applying rpcbind workaround${endColor}"
        echo 'systemctl start rpcbind'
        systemctl start rpcbind
        if [ $? -ne 0 ]; then
            echo -e "${red}Problem with rpcbind start${endColor}"
            curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=RpcStart%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
            exit 1
        fi
        sed -i -e "\|^systemctl start rpcbind|d" /etc/rc.d/rc.local
        echo 'echo "systemctl start rpcbind" >> /etc/rc.d/rc.local && chmod +x /etc/rc.d/rc.local'
        echo "systemctl start rpcbind" >> /etc/rc.d/rc.local && chmod +x /etc/rc.d/rc.local
        if [ $? -ne 0 ]; then
            echo -e "${red}Problem with installing rpcbind autostart workaround${endColor}"
            curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=RpcWorkaround%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
            exit 1
        fi
        echo -e "${green}Done${endColor}"
    fi
fi

# Startup serviced services
echo -e "${yellow}3.9 Start the Control Center service${endColor}"
if [ "$hostos" == "redhat" ]; then
    echo "systemctl enable serviced && systemctl start serviced"
    systemctl enable serviced && systemctl start serviced
elif [ "$hostos" == "ubuntu" ]; then
    echo 'service serviced status'
    output=$(service serviced status)
    com_ret=$?
    echo "$output"
    substring="stop"
    if [ "$output" != "${output%$substring*}" ]; then
        echo "start serviced"
        start serviced
    fi
fi
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with starting of serviced${endColor}"
    curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=ServicedStart%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

# exit host installation
if [ ! -z "$MHOST" ]; then
    echo -e "${green}Control Center installation on the host completed${endColor}"
    echo -e "${green}Please visit Control Center${endColor}"
    echo -e "${green}You can check status of serviced: systemctl status serviced${endColor}"
    echo -e "Install guide: ${install_doc}"
    echo -e "${blue}Credit: www.monitoringartist.com${endColor}"
    echo -e "${blue}Get your own Zenoss 5 Core taster instance in 10 minutes: www.zenoss5taster.com${endColor}"
    exit 0
fi

echo -e "${blue}4 ${zenoss_installation} deployement - (`date -R`)${endColor}"

echo -e "${yellow}4.1 Adding current host to the default resource pool${endColor}"
echo -e "${yellow}Please be patient, because docker image zenoss/serviced-isvcs must be downloaded before first start.${endColor}"
echo -e "${yellow}You can check progress in new console: ${log_watch}${endColor}"
echo -e "${yellow}Script is trying to check status every 10s. Timeout for this step is 15 minutes.${endColor}"
echo "serviced host list 2>&1"
test=$(serviced host list 2>&1)
# wait for serviced start
retry=1
while [ "$test" = "rpc: can't find service Master.GetHosts" ] || [[ "$test" =~ "could not create a client to the master: dial tcp" ]] && [ $retry -lt $retries_max ]
do
    echo $test
    echo "#${retry}: This is not a problem, because Control Centre service is not fully started, I'm trying in ${sleep_duration} seconds"
    echo "Message from author of autodeploy script: Keep calm and be patient! - http://www.keepcalmandposters.com/posters/38112.png"
    echo -n "Last serviced log: "
    eval $log_watch_last_line
    retry=$(( $retry + 1 ))
    sleep $sleep_duration
    test=$(serviced host list 2>&1)
done
if [ "$test" = "no hosts found" ]; then
    echo "serviced host add $hostname:4979 default"
    serviced host add $hostname:4979 default
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with command: serviced host add $privateipv4:4979 default${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=ServicedAddHost%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        exit 1
    else
        echo -e "${green}Done${endColor}"
    fi
else
    echo "echo \"$test\" | grep -v loopback | wc -l"
    test2=$(echo "$test" | grep -v loopback | wc -l)
    if [ "$test2" -gt "1" ]; then
        echo -e "${yellow}Skipping - some host is deployed already${endColor}"
        echo -e "${green}Done${endColor}"
    else
        echo -e "${red}Problem with adding a host - check output from test: $test${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=ServicedAddHost2%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        exit 1
    fi
fi

echo -e "${yellow}4.2 Deploy ${zenoss_template} application (the deployment step can take 15-30 minutes)${endColor}"
echo -e "${yellow}Please be patient, because all Zenoss docker images must be downloaded before first start.${endColor}"
echo -e "${yellow}Warning: Could not find container for isvc logstash is not a problem - please be only patient.${endColor}"
echo -e "${yellow}Progress from serviced log file is presented. No timeout for this step.${endColor}"
echo "serviced template list 2>&1 | grep \"${zenoss_template}\" | awk '{print \$1}'"
TEMPLATEID=$(serviced template list 2>&1 | grep "${zenoss_template}" | awk '{print $1}')
echo 'serviced service list 2>/dev/null | wc -l'
services=$(serviced service list 2>/dev/null | wc -l)
if [ "$services" == "0" ]; then
    echo "serviced template deploy $TEMPLATEID default zenoss"
    # log watching in background
    bgjobs=$(jobs -p | wc -l)
    ((bgjobs++))
    $log_watch &
    serviced template deploy $TEMPLATEID default zenoss
    rc=$?
    # kill log watching
    kill %${bgjobs}
    sleep 5
    if [ $rc -ne 0 ]; then
        echo -e "${red}Problem with command: serviced template deploy $TEMPLATEID default zenoss${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=ServicedTempDeploy%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        exit 1
    else
        echo -e "${green}Done${endColor}"
    fi
else
    if [ "$services" -gt "0" ]; then
        echo -e "${yellow}Skipping - some services are already deployed, check: serviced service list${endColor}"
        echo -e "${green}Done${endColor}"
    else
        echo -e "${red}Skipping deploying an application - check output from template test: $TEMPLATEID${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=ServicedTempDeploy2%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
        exit 1
    fi
fi

echo -e "${yellow}5 Tuning ${zenoss_template}${endColor}"

# Quilt packages
echo -e "${yellow}5.1 Installing the Quilt package${endColor}"
echo "Creating /tmp/quilt.txt"
cat > /tmp/quilt.txt << EOF
DESCRIPTION quilt.txt -- add Quilt to a Zenoss image
VERSION zenoss-quilt-1.0
REQUIRE_SVC
SNAPSHOT

# Download the EPEL RPM
SVC_EXEC COMMIT ${zenoss_template} yum install -y epel-release
# Download repository metadata
SVC_EXEC COMMIT ${zenoss_template} yum makecache -y
# Install quilt
SVC_EXEC COMMIT ${zenoss_template} yum install -y quilt
# Remove EPEL
SVC_EXEC COMMIT ${zenoss_template} yum erase -y epel-release
# Clean up yum caches
SVC_EXEC COMMIT ${zenoss_template} yum clean all
EOF

echo "Syntax verification of /tmp/quilt.txt"
serviced script parse /tmp/quilt.txt
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with syntax verification of /tmp/quilt.txt${endColor}"
    rm -rf /tmp/quilt.txt
fi
echo "Installing the Quilt package"
serviced script run /tmp/quilt.txt --service ${zenoss_template}
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with installing the Quilt package${endColor}"
    rm -rf /tmp/quilt.txt
fi
rm -rf /tmp/quilt.txt
echo -e "${green}Done${endColor}"

# Percona toolkit
echo -e "${yellow}5.2 Installing the Percona Toolkit${endColor}"
echo "serviced service list | grep -i mariadb | awk '{print $1}' | sort -r | grep -i 'mariadb' | head -n 1"
mservice=$( serviced service list | grep -i mariadb | awk '{print $1}' | sort -r | grep -i 'mariadb' | head -n 1)
echo "serviced service start $mservice"
serviced service start $mservice
echo "serviced service run zope install-percona"
serviced service run zope install-percona
# exit code 1 always
if [ $? -ne 1 ]; then
    echo -e "${red}Problem with installing the Percona Toolkit${endColor}"
fi
echo "serviced service stop $mservice"
serviced service stop $mservice
echo -e "${green}Done${endColor}"

echo -e "${yellow}5.4 Deleting the RabbitMQ guest user account${endColor}"
serviced service start $(serviced service list | grep -i rabbitmq | awk '{print $2}')
sleep 30
serviced service attach $(serviced service list | grep -i rabbitmq | awk '{print $2}') rabbitmqctl delete_user guest
serviced service stop $(serviced service list | grep -i rabbitmq | awk '{print $2}')
echo -e "${green}Done${endColor}"

echo -e "${yellow}5.5 Port forwarding${endColor}"
ipv4forwarding=$(sysctl net.ipv4.conf.all.forwarding)
if [ "$ipv4forwarding" != "net.ipv4.conf.all.forwarding = 1" ]; then
    sysctl net.ipv4.conf.all.forwarding=1
    sed -i -e "\|^net.ipv4.conf.all.forwarding |d" /etc/sysctl.conf
    echo "net.ipv4.conf.all.forwarding = 1" >> /etc/sysctl.conf
    echo -e "${green}Done${endColor}"
else
    echo -e "${green}Done${endColor} - already enabled"
fi

if [ "$zenoss_impact" == "$zenoss_impact_enterprise" ]; then
    echo -e "${yellow}6 Pull Service Impact Docker image (the deployment step can take 3-5 minutes)${endColor}"
    echo "docker pull $zenoss_impact"
    docker pull $zenoss_impact
    if [ $rc -ne 0 ]; then
        echo -e "${red}Problem with pulling Service Impact Docker image${endColor}"
        curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=ImpactPull2%20error&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
    else
        echo -e "${green}Done${endColor}"
    fi
fi

echo -e "${yellow}7 Extra templates${endColor}"
domains=" "
echo -e "${yellow}Adding Zabbix 2.4 template${endColor}"
echo "Visit: https://github.com/monitoringartist/control-center-zabbix"
curl -O https://raw.githubusercontent.com/monitoringartist/control-center-zabbix/master/Control-Center-Zabbix-2.4-template.json
echo "serviced template add Control-Center-Zabbix-2.4-template.json"
serviced template add Control-Center-Zabbix-2.4-template.json
rm -rf Control-Center-Zabbix-2.4-template.json
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Extra%20template&el=zabbix&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
echo -e "${green}Done${endColor}"

echo -e "${yellow}Adding Elasticsearch 2.0 template${endColor}"
echo "Visit: https://github.com/monitoringartist/control-center-elasticsearch"
curl -O https://raw.githubusercontent.com/monitoringartist/control-center-elasticsearch/master/Control-Center-Eleasticsearch-2.0-template.json
echo "serviced template add Control-Center-Eleasticsearch-2.0-template.json"
serviced template add Control-Center-Eleasticsearch-2.0-template.json
rm -rf Control-Center-Eleasticsearch-2.0-template.json
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Extra%20template&el=elasticsearch&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
echo -e "${green}Done${endColor}"

echo -e "${yellow}Adding Zenoss-Searcher template${endColor}"
echo "Visit: https://github.com/monitoringartist/control-center-zenoss-searcher"
curl -O https://raw.githubusercontent.com/monitoringartist/control-center-zenoss-searcher/master/Control-Center-Zenoss-Searcher-template.json
echo "serviced template add Control-Center-Zenoss-Searcher-template.json"
serviced template add Control-Center-Zenoss-Searcher-template.json
rm -rf Control-Center-Zenoss-Searcher-template.json
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Extra%20template&el=zenoss-searcher&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
echo -e "${green}Done${endColor}"

# loop for extra template deployement
declare -a extras=("zabbix" "elasticsearch" "zenoss-searcher")
for extraapp in "${extras[@]}"
do
    substring=",${extraapp},"
    if [ "$EXTRA" != "${EXTRA%$substring*}" ]; then
        echo -e "${yellow}Deploying ${extraapp} template${endColor}"
        domains="${domains}${extraapp}.$hostname "
        echo "serviced template list 2>&1 | grep -i \"${extraapp}\" | awk '{print \$1}'"
        TEMPLATEID=$(serviced template list 2>&1 | grep -i "${extraapp}" | awk '{print $1}')
        echo 'serviced service list 2>/dev/null | grep -i ${extraapp} | wc -l'
        services=$(serviced service list 2>/dev/null | grep -i ${extraapp} | wc -l)
        if [ "$services" == "0" ]; then
            echo "serviced template deploy $TEMPLATEID default ${extraapp}"
            # log watching in background
            bgjobs=$(jobs -p | wc -l)
            ((bgjobs++))
            $log_watch &
            serviced template deploy $TEMPLATEID default ${extraapp}
            rc=$?
            # kill log watching
            kill %${bgjobs}
            sleep 5
            if [ $rc -ne 0 ]; then
                echo -e "${red}Problem with command: serviced template deploy $TEMPLATEID default ${extraapp}${endColor}"
                curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Extra%20error%20${extraapp}&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
                #exit 1
                echo -e "${green}Done${endColor} with problem"
            else
                curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Error&el=Extra%20OK%20${extraapp}&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
                echo -e "${green}Done${endColor}"
            fi
        else
            if [ "$services" -gt "0" ]; then
                echo -e "${yellow}Skipping - some ${extraapp} services are already deployed, check: serviced service list${endColor}"
                echo -e "${green}Done${endColor}"
            else
                echo -e "${red}Skipping deploying an application - check output from template test: $TEMPLATEID${endColor}"
                #exit 1
                echo -e "${green}Done${endColor} with problem"
            fi
        fi
    fi
done

echo -e "${blue}5 Final overview - (`date -R`)${endColor}"
echo -e "${green}Control Center & ${zenoss_installation} installation completed${endColor}"
echo -e "${green}Set password for Control Center ${user} user: passwd ${user}${endColor}"
echo -e "${green}Please visit Control Center https://$publicipv4/ in your favorite web browser to complete setup, log in with ${user} user${endColor}"
echo -e "${green}Add following line to your hosts file:${endColor}"
echo -e "${green}$publicipv4 $hostname hbase.$hostname opentsdb.$hostname rabbitmq.$hostname zenoss5.$hostname$domains${endColor}"
echo -e "${green}or edit /etc/default/serviced and set SERVICED_VHOST_ALIASES to your FQDN${endColor}"
# selinux test
output=$(id)
substring="context="
if [ "$output" != "${output%$substring*}" ]; then
    echo -e "${red}Please also reboot machine, because SELINUX is still active!${endColor}"
fi
echo -e "Install guide: ${install_doc}"
echo -e "${blue}Credit: www.monitoringartist.com${endColor}"
echo -e "${blue}Get your own Zenoss 5 Core taster instance in 10 minutes: www.zenoss5taster.com${endColor}"
echo -e "${yellow}${advert}${endColor}"
duration=$(($(date +%s) - $starttimestamp))
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Installation&ea=Stop%20OK&el=Install%20OK%20${duration}&ev=${duration}&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy"
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Stat&ea=OS&el=${hostos}&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Stat&ea=Duration&el=${duration}%20sec&ev=${duration}&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Stat&ea=CPU&el=${cpus}%20count&ev=${cpus}&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Stat&ea=RAM&el=${rams}%20GB&ev=${rams}&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
if [ "$hostos" == "redhat" ]; then
    serviced_version=serviced%20$(rpm -qi serviced | grep Version | awk -F: '{print $2}' | tr -d ' ')
    zenoss_version=${zenoss_package}%20$(rpm -qi $zenoss_package | grep Version | awk -F: '{print $2}' | tr -d ' ')
else
    serviced_version=serviced%20$(dpkg -s serviced | grep Version | awk -F: '{print $2}' | tr -d ' ')
    zenoss_version=${zenoss_package}%20$(dpkg -s $zenoss_package | grep Version | awk -F: '{print $2}' | tr -d ' ')
fi
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Stat&ea=Zenoss%20version&el=${zenoss_version}&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
curl -ks -o /dev/null "http://www.google-analytics.com/r/collect?v=1&tid=UA-68890375-1&cid=${cid}&t=event&ec=Stat&ea=Serviced%20version&el=${serviced_version}&ev=1&dp=%2F&dl=http%3A%2F%2Fgithub.com%2Fmonitoringartist%2Fzenoss5-core-autodeploy" &> /dev/null
# finish ring
printf '\a'; sleep 0.1; printf '\a'; sleep 0.1; printf '\a'; sleep 0.1; printf '\a';