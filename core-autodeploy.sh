#!/bin/bash

# Script for Control Center and Zenoss Core 5/Zenoss Resource Manager 5 deployement
# Copyright (C) 2015 Jan Garaj - www.jangaraj.com

# Variables
cpus_min=4
rams_min=20 #GB
root_fs_min_size=30 #GB
root_fs_type="xfs"
docker_fs_min_size=30 #GB
docker_fs_type="btrfs"
serviced_fs_min_size=30 #GB
serviced_fs_type="xfs"
servicedvolumes_fs_min_size=1 #GB
servicedvolumes_fs_type="btrfs"
servicedbackups_fs_min_size=1 #GB
servicedbackups_fs_type="xfs"
mount_parameters_btrfs="rw,noatime,nodatacow 0 0"
mount_parameters_xfs="defaults,noatime 0 0"
g2k=1048576
user="ccuser"
version="2015-04-24"
retries_max=90
sleep_duration=10
install_doc="http://wiki.zenoss.org/download/core/docs/Zenoss_Core_Installation_Guide_r5.0.0_latest.pdf"
install_doc_enterprise="Please contact your Zenoss representative for Zenoss Resource Manager 5 documentation"
zenoss_package="zenoss-core-service"
zenoss_package_enterprise="zenoss-resmgr-service"
zenoss_installation="Zenoss Core 5"
zenoss_installation_enterprise="Zenoss Resource Manager 5"
zenoss_template="Zenoss.core"
zenoss_template_enterprise="Zenoss.resmgr"
zenoss_impact=""
zenoss_impact_enterprise="zenoss/impact_5.0:5.0.0.0.0"
docker_registry_user=""
docker_registry_email=""
docker_registry_password=""
MHOST=""
    
green='\e[0;32m'
yellow='\e[0;33m'
red='\e[0;31m'
blue='\e[0;34m'
endColor='\e[0m'

echo -e "${yellow}Autodeploy script ${version} for Control Center master host and Zenoss Core 5/Zenoss Resource Manager 5${endColor}"
echo -e "Install guide: ${install_doc}"

echo -e "${yellow}Requirements:${endColor}
Min number of available CPUs: ${cpus_min}
Min size of available RAM:    ${rams_min}GB
These filesystems must be mounted with correct type and size:
Filesystem                  Type	Min size
/                           ${root_fs_type}		${root_fs_min_size}GB
/var/lib/docker             ${docker_fs_type}	${docker_fs_min_size}GB
/opt/serviced/var           ${serviced_fs_type}		${serviced_fs_min_size}GB
/opt/serviced/var/volumes   ${servicedvolumes_fs_type}	${servicedvolumes_fs_min_size}GB
/opt/serviced/var/backups   ${servicedbackups_fs_type}	${servicedbackups_fs_min_size}GB"

# lang check, only en_GB.UTF-8/en_US.UTF-8 are supported
languages=$(locale | awk -F'=' '{print $2}' | tr -d '"' | grep -v '^$' | sort | uniq | tr -d '\r' | tr -d '\n')
if [ "$languages" != "en_GB.UTF-8" ] && [ "$languages" != "en_US.UTF-8" ]; then
    echo -e "${yellow}Warning: some non US/GB English or non UTF-8 locales are detected (see output from the command locale).\nOnly en_GB.UTF-8/en_US.UTF-8 are supported in core-autodeploy.sh script.\nYou can try to continue. Do you want to continue (y/n)?${endColor}"
    read answer    
    if echo "$answer" | grep -iq "^y" ;then
        echo " ... continuing"  
    else
        exit 1
    fi
fi
          
while getopts "i:r:u:e:p:h:d:s:v:b:" arg; do
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
      # -e <docker registry password>
      docker_registry_password=$OPTARG
      ;;
    h)
      # -h <IP of CC master>
      MHOST=$OPTARG
      ;;                            
    d)
      path="/var/lib/docker"
      rfs=$docker_fs_type
      dev=$OPTARG
      echo -e "${yellow}0 Preparing ${path} filesystem - device: ${dev}${endColor}"
      fs=$(df -T | grep ' \/var\/lib\/docker$' | awk '{print $2}')
      if [ ! -z "$fs" ]; then
          echo -e "${path} filesystem is already mounted, skipping creating this filesystem"
      else
          # mount point
          if [ ! -d $path ]; then
              echo "mkdir -p ${path}" 
              mkdir -p ${path}
              if [ $? -ne 0 ]; then
                  echo -e "${red}Problem with creating mountpoint ${path}${endColor}"
                  exit 1
              fi
          fi
          # mkfs
          echo -e "${dev} will be formated to ${rfs}. All current data on ${dev} will be lost and /etc/fstab will be updated. Do you want to continue (y/n)?"
          read answer    
          if echo "$answer" | grep -iq "^y" ;then
              if [ "${rfs}" == "btrfs" ]; then
                  echo "mkfs -t ${rfs} -f --nodiscard ${dev}"
                  mkfs -t ${rfs} -f --nodiscard ${dev}
                  mount_parameters=$mount_parameters_btrfs
              else
                  echo "mkfs -t ${rfs} -f ${dev}"
                  mkfs -t ${rfs} -f ${dev}              
                  mount_parameters=$mount_parameters_xfs
              fi
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with formating ${dev}${endColor}"
                exit 1
              fi
              # fstab
              echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
              sed -i -e "\|^$dev|d" /etc/fstab                  
              echo "echo \"${dev} ${path} ${rfs} ${mount_parameters}\" >> /etc/fstab"
              echo "${dev} ${path} ${rfs} ${mount_parameters}" >> /etc/fstab
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with updating /etc/fstab for ${dev}${endColor}"
                exit 1
              fi
              # mount
              echo "mount ${path}"
              mount ${path}
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with mounting ${path}${endColor}"
                exit 1
              fi
          else
              exit 1
          fi
        fi             
      ;;
    s)
      path="/opt/serviced/var"
      rfs=$serviced_fs_type
      dev=$OPTARG
      echo -e "${yellow}0 Preparing ${path} filesystem - device: ${dev}${endColor}"
      fs=$(df -T | grep ' \/opt\/serviced\/var$' | awk '{print $2}')
      if [ ! -z "$fs" ]; then
          echo -e "${path} filesystem is already mounted, skipping creating this filesystem"
      else
          # mount point
          if [ ! -d $path ]; then
              echo "mkdir -p ${path}" 
              mkdir -p ${path}
              if [ $? -ne 0 ]; then
                  echo -e "${red}Problem with creating mountpoint ${path}${endColor}"
                  exit 1
              fi
          fi
          # mkfs
          echo -e "${dev} will be formated to ${rfs}. All current data on ${dev} will be lost and /etc/fstab will be updated. Do you want to continue (y/n)?"
          read answer    
          if echo "$answer" | grep -iq "^y" ;then
              if [ "${rfs}" == "btrfs" ]; then
                  echo "mkfs -t ${rfs} -f --nodiscard ${dev}"
                  mkfs -t ${rfs} -f --nodiscard ${dev}
                  mount_parameters=$mount_parameters_btrfs
              else
                  echo "mkfs -t ${rfs} -f ${dev}"
                  mkfs -t ${rfs} -f ${dev}
                  mount_parameters=$mount_parameters_xfs              
              fi
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with formating ${dev}${endColor}"
                exit 1
              fi
              # fstab
              echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
              sed -i -e "\|^$dev|d" /etc/fstab                  
              echo "echo \"${dev} ${path} ${rfs} ${mount_parameters}\" >> /etc/fstab"
              echo "${dev} ${path} ${rfs} ${mount_parameters}" >> /etc/fstab
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with updating /etc/fstab for ${dev}${endColor}"
                exit 1
              fi
              # mount
              echo "mount ${path}"
              mount ${path}
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with mounting ${path}${endColor}"
                exit 1
              fi
          else
              exit 1
          fi
        fi             
      ;;
    v)
      path="/opt/serviced/var/volumes"
      rfs=$servicedvolumes_fs_type
      dev=$OPTARG
      echo -e "${yellow}0 Preparing ${path} filesystem - device: ${dev}${endColor}"
      fs=$(df -T | grep ' \/opt\/serviced\/var\/volumes$' | awk '{print $2}')
      if [ ! -z "$fs" ]; then
          echo -e "${path} filesystem is already mounted, skipping creating this filesystem"
      else
          # mount point
          if [ ! -d $path ]; then
              echo "mkdir -p ${path}" 
              mkdir -p ${path}
              if [ $? -ne 0 ]; then
                  echo -e "${red}Problem with creating mountpoint ${path}${endColor}"
                  exit 1
              fi
          fi
          # mkfs
          echo -e "${dev} will be formated to ${rfs}. All current data on ${dev} will be lost and /etc/fstab will be updated. Do you want to continue (y/n)?"
          read answer    
          if echo "$answer" | grep -iq "^y" ;then
              if [ "${rfs}" == "btrfs" ]; then
                  echo "mkfs -t ${rfs} -f --nodiscard ${dev}"
                  mkfs -t ${rfs} -f --nodiscard ${dev}
                  mount_parameters=$mount_parameters_btrfs
              else
                  echo "mkfs -t ${rfs} -f ${dev}"
                  mkfs -t ${rfs} -f ${dev}              
                  mount_parameters=$mount_parameters_xfs
              fi
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with formating ${dev}${endColor}"
                exit 1
              fi
              # fstab
              echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
              sed -i -e "\|^$dev|d" /etc/fstab                  
              echo "echo \"${dev} ${path} ${rfs} ${mount_parameters}\" >> /etc/fstab"
              echo "${dev} ${path} ${rfs} ${mount_parameters}" >> /etc/fstab
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with updating /etc/fstab for ${dev}${endColor}"
                exit 1
              fi
              # mount
              echo "mount ${path}"
              mount ${path}
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with mounting ${path}${endColor}"
                exit 1
              fi
          else
              exit 1
          fi
        fi                         
      ;;
    b)
      path="/opt/serviced/var/backups"
      rfs=$servicedbackups_fs_type
      dev=$OPTARG
      echo -e "${yellow}0 Preparing ${path} filesystem - device: ${dev}${endColor}"
      fs=$(df -T | grep ' \/opt\/serviced\/var\/backups$' | awk '{print $2}')
      if [ ! -z "$fs" ]; then
          echo -e "${path} filesystem is already mounted, skipping creating this filesystem"
      else
          # mount point
          if [ ! -d $path ]; then
              echo "mkdir -p ${path}" 
              mkdir -p ${path}
              if [ $? -ne 0 ]; then
                  echo -e "${red}Problem with creating mountpoint ${path}${endColor}"
                  exit 1
              fi
          fi
          # mkfs
          echo -e "${dev} will be formated to ${rfs}. All current data on ${dev} will be lost and /etc/fstab will be updated. Do you want to continue (y/n)?"
          read answer    
          if echo "$answer" | grep -iq "^y" ;then
              if [ "${rfs}" == "btrfs" ]; then
                  echo "mkfs -t ${rfs} -f --nodiscard ${dev}"
                  mkfs -t ${rfs} -f --nodiscard ${dev}
                  mount_parameters=$mount_parameters_btrfs
              else
                  echo "mkfs -t ${rfs} -f ${dev}"
                  mkfs -t ${rfs} -f ${dev}              
                  mount_parameters=$mount_parameters_xfs
              fi
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with formating ${dev}${endColor}"
                exit 1
              fi
              # fstab
              echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
              sed -i -e "\|^$dev|d" /etc/fstab                  
              echo "echo \"${dev} ${path} ${rfs} ${mount_parameters}\" >> /etc/fstab"
              echo "${dev} ${path} ${rfs} ${mount_parameters}" >> /etc/fstab
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with updating /etc/fstab for ${dev}${endColor}"
                exit 1
              fi
              # mount
              echo "mount ${path}"
              mount ${path}
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with mounting ${path}${endColor}"
                exit 1
              fi
          else
              exit 1
          fi
        fi      
      ;;            
  esac
done

echo -e "${blue}1 Checks - (`date -R`)${endColor}"
echo -e "${yellow}1.1 Root permission check${endColor}"
if [ "$EUID" -ne 0 ]; then
  echo -e "${red}Please run as root or use sudo${endColor}"
  exit 1
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}1.2 Architecture check${endColor}"
arch=$(uname -m)
if [ ! "$arch" = "x86_64" ]; then
	echo -e "${red}Not supported architecture $arch. Architecture x86_64 only is supported.${endColor}"
    exit 1
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}1.3 OS version check${endColor}"
if [ -f /etc/redhat-release ]; then
    elv=`cat /etc/redhat-release | gawk 'BEGIN {FS="release "} {print $2}' | gawk 'BEGIN {FS="."} {print $1}'`
    if [ $elv -ne 7 ]; then
	    echo -e "${red}Not supported OS version. Only RedHat 7 and CentOS 7 are supported by autodeploy script at the moment.${endColor}"
        exit 1
    fi
else
	echo -e "${red}Not supported OS version. Only RedHat 7 and CentOS 7 are supported by autodeploy script at the moment.${endColor}"
    exit 1   
fi
echo -e "${green}Done${endColor}"


echo -e "${yellow}1.4 CPU check${endColor}"
cpus=$(nproc)
if [ $cpus -lt $cpus_min ]; then
    echo -e "${red}Only ${cpus} CPUs have been detected, but at least $cpus_min are required. Do you want to continue (y/n)?${endColor}"
    read answer    
    if echo "$answer" | grep -iq "^y" ;then
        echo " ... continuing"
    else
        exit 1
    fi    
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}1.5 RAM check${endColor}"
rams=$(free -g | grep 'Mem' | awk '{print $2}') 
if [ $rams -lt $rams_min ]; then
    echo -e "${red}Only ${rams} GB of RAM has been detected, but at least 20GB is recommended. Do you want to continue (y/N)?${endColor}"
    read answer    
    if echo "$answer" | grep -iq "^y" ;then
        echo " ... continuing"
    else
        exit 1
    fi    
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}1.6 / filesystem check${endColor}"
fs=$(df -T | grep ' \/$' | awk '{print $2}')
if [ "$fs" != "$root_fs_type" ]; then
    echo -e "${red}${fs} / filesystem detected, but ${root_fs_type} is required${endColor}"
    exit 1    
fi
ss=$(df -T | grep ' \/$' | awk '{print $3}')
mss=$(($root_fs_min_size * $g2k))
if [ $ss -lt $mss ]; then
    echo -e "${red}/ filesystem size is less than required ${root_fs_min_size}GB. Do you want to continue (y/N)?${endColor}"
    read answer    
    if echo "$answer" | grep -iq "^y" ;then
        echo " ... continuing"
    else
        exit 1
    fi    
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}1.7 /var/lib/docker filesystem check${endColor}"
fs=$(df -T | grep ' \/var\/lib\/docker$' | awk '{print $2}')
if [ -z "$fs" ]; then
    echo -e "${red}/var/lib/docker filesystem was not detected${endColor}"
    exit 1
fi
if [ "$fs" != "$docker_fs_type" ]; then
    echo -e "${red}${fs} /var/lib/docker filesystem detected, but ${docker_fs_type} is required${endColor}"
    exit 1    
fi
ss=$(df -T | grep ' \/var\/lib\/docker$' | awk '{print $3}')
mss=$(($docker_fs_min_size * $g2k))
if [ $ss -lt $mss ]; then
    echo -e "${red}/var/lib/docker filesystem size is less than required ${docker_fs_min_size}GB. Do you want to continue (y/N)?${endColor}"
    read answer    
    if echo "$answer" | grep -iq "^y" ;then
        echo " ... continuing"
    else
        exit 1
    fi        
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}1.8 /opt/serviced/var filesystem check${endColor}"
fs=$(df -T | grep ' \/opt\/serviced\/var$' | awk '{print $2}')
if [ -z "$fs" ]; then
    echo -e "${red}/opt/serviced/var filesystem was not detected${endColor}"
    exit 1
fi
if [ "$fs" != "$serviced_fs_type" ]; then
    echo -e "${red}${fs} /opt/serviced/var filesystem detected, but ${serviced_fs_type} is required${endColor}"
    exit 1    
fi
ss=$(df -T | grep ' \/opt\/serviced\/var$' | awk '{print $3}')
mss=$(($serviced_fs_min_size * $g2k))
if [ $ss -lt $mss ]; then
    echo -e "${red}/opt/serviced/var filesystem size is less than required ${serviced_fs_min_size}GB. Do you want to continue (y/N)?${endColor}"
    read answer    
    if echo "$answer" | grep -iq "^y" ;then
        echo " ... continuing"
    else
        exit 1
    fi    
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}1.9 /opt/serviced/var/volumes filesystem check${endColor}"
fs=$(df -T | grep ' \/opt\/serviced\/var\/volumes$' | awk '{print $2}')
if [ -z "$fs" ]; then
    echo -e "${red}/opt/serviced/var/volumes filesystem was not detected${endColor}"
    echo -e "${yellow}Do you want to continue (y/n)?${endColor}"
    read answer    
    if echo "$answer" | grep -iq "^y" ;then
        echo " ... continuing"  
        # mkdir -p /opt/serviced/var/volumes
    else
        exit 1
    fi
else
    if [ "$fs" != "$servicedvolumes_fs_type" ]; then
        echo -e "${red}${fs} /opt/serviced/var/volumes filesystem detected, but ${servicedvolumes_fs_type} is required${endColor}"
        exit 1    
    fi
    ss=$(df -T | grep ' \/opt\/serviced\/var\/volumes$' | awk '{print $3}')
    mss=$(($servicedvolumes_fs_min_size * $g2k))
    if [ $ss -lt $mss ]; then
        echo -e "${red}/opt/serviced/var/volumes filesystem size is less than required ${servicedvolumes_fs_min_size}GB. Do you want to continue (y/N)?${endColor}"
        read answer    
        if echo "$answer" | grep -iq "^y" ;then
            echo " ... continuing"
        else
            exit 1
        fi    
    else
      echo -e "${green}Done${endColor}"
    fi    
fi


echo -e "${yellow}1.10 /opt/serviced/var/backups filesystem check${endColor}"
fs=$(df -T | grep ' \/opt\/serviced\/var\/backups$' | awk '{print $2}')
if [ -z "$fs" ]; then
    echo -e "${red}/opt/serviced/var/backups filesystem was not detected${endColor}"
    echo -e "${yellow}Do you want to continue (y/n)?${endColor}"
    read answer    
    if echo "$answer" | grep -iq "^y" ;then
        echo " ... continuing"  
        # mkdir -p /opt/serviced/var/backups
    else
        exit 1
    fi
else
    if [ "$fs" != "$servicedbackups_fs_type" ]; then
        echo -e "${red}${fs} /opt/serviced/var/backups filesystem detected, but ${servicedbackups_fs_type} is required${endColor}"
        exit 1    
    fi
    ss=$(df -T | grep ' \/opt\/serviced\/var\/backups$' | awk '{print $3}')
    mss=$(($servicedbackups_fs_min_size * $g2k))
    if [ $ss -lt $mss ]; then
        echo -e "${red}/opt/serviced/var/backups filesystem size is less than required ${servicedbackups_fs_min_size}GB. Do you want to continue (y/N)?${endColor}"
        read answer    
        if echo "$answer" | grep -iq "^y" ;then
            echo " ... continuing"
        else
            exit 1
        fi    
    else
      echo -e "${green}Done${endColor}"
    fi
fi

echo -e "${blue}2 Preparing the host - (`date -R`)${endColor}"

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
 
hostname=$(uname -n)
if [ "$hostname" == "localhost" ] || [ "$hostname" == "localhost.localdomain" ]; then
    hostname=$(echo $publicipv4 | tr '.' '-')
    hostname="ip-$hostname"
fi
echo "Hostname: $hostname"
grep "$privateipv4 $hostname" /etc/hosts
if [ $? -ne 0 ]; then
    echo "echo \"$privateipv4 $hostname\" >> /etc/hosts"
    echo "$privateipv4 $hostname" >> /etc/hosts
fi
echo "Public IPv4: $publicipv4"
echo "Private IPv4: $privateipv4"
echo -e "${green}Done${endColor}"

echo -e "${yellow}2.2 Disable the firewall${endColor}"
echo 'systemctl stop firewalld && systemctl disable firewalld'
systemctl stop firewalld && systemctl disable firewalld
echo -e "${green}Done${endColor}"

echo -e "${yellow}2.3 Enable persistent storage for log files${endColor}"
echo 'mkdir -p /var/log/journal && systemctl restart systemd-journald'
mkdir -p /var/log/journal && systemctl restart systemd-journald
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with enabling persistent log storage${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}2.4 Disable selinux${endColor}"
test=$(test -f /etc/selinux/config && grep '^SELINUX=' /etc/selinux/config)
if [ ! -z "$test" ] && [ "$test" != "SELINUX=disabled" ]; then
    # TODO restart required when disabling selinux (???)
    echo "sed -i.$(date +\"%j-%H%M%S\") -e 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config && grep '^SELINUX=' /etc/selinux/config"
    sed -i.$(date +"%j-%H%M%S") -e 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config && grep '^SELINUX=' /etc/selinux/config
    echo -e "${green}Done${endColor}"
else
    echo -e "${green}Done${endColor} - disabled already"
fi

echo -e "${yellow}2.5 Download and install the Zenoss repository package${endColor}"
echo 'rpm -ivh http://get.zenoss.io/yum/zenoss-repo-1-1.x86_64.rpm'
output=$(rpm -ivh http://get.zenoss.io/yum/zenoss-repo-1-1.x86_64.rpm 2>&1)
com_ret=$?
echo "$output"
substring="is already installed"
if [ $com_ret -ne 0 ] && [ "$output" == "${output%$substring*}" ]; then
    echo -e "${red}Problem with installing Zenoss repository${endColor}"
    exit 1
else
    yum clean all &>/dev/null
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}2.6 Install and start the dnsmasq package${endColor}"
echo 'yum install -y dnsmasq && systemctl enable dnsmasq && systemctl start dnsmasq'
yum install -y dnsmasq && systemctl enable dnsmasq && systemctl start dnsmasq
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with installing dnsmasq package${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}2.7 Install and start the ntp package${endColor}"
echo 'yum install -y ntp && systemctl enable ntpd'
yum install -y ntp && systemctl enable ntpd
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with installing ntp package${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}2.8 ntpd autostart workaround${endColor}"
echo 'echo "systemctl start ntpd" >> /etc/rc.d/rc.local && chmod +x /etc/rc.d/rc.local'
sed -i -e "\|^systemctl start ntpd|d" /etc/rc.d/rc.local
echo "systemctl start ntpd" >> /etc/rc.d/rc.local && chmod +x /etc/rc.d/rc.local
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with installing ntpd autostart workaround${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}2.9 ntpd start${endColor}"
echo 'systemctl start ntpd'
systemctl start ntpd
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with ntpd start${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

echo -e "${blue}3 Installing on the master host - (`date -R`)${endColor}"

echo -e "${yellow}3.1 Install Control Center, Zenoss Core, and Docker${endColor}"
echo "yum --enablerepo=zenoss-stable install -y ${zenoss_package}"
yum --enablerepo=zenoss-stable install -y ${zenoss_package}
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with installing Control Center, Zenoss Core and Docker${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}3.2 Start Docker${endColor}"
echo 'systemctl enable docker && systemctl start docker'
systemctl enable docker && systemctl start docker
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with starting of Docker${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

if [ "$zenoss_package" == "$zenoss_package_enterprise" ] && [ -z "$MHOST" ]; then
    # docker login
    echo -e "${yellow}Authenticate to the Docker Hub repository${endColor}"  
    mySetting=$HISTCONTROL; export HISTCONTROL=ignorespace
    myUser=$docker_registry_user
    myEmail=$docker_registry_email
    myPass=$docker_registry_password
    # turn off history substitution using - problem with specific passwords
    set +H
    systemctl start docker
    # sleep
    sleep 10
    sudo sh -c "docker login -u $myUser -e $myEmail -p '$myPass'"
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with authentication to the Docker Hub${endColor}"
        exit 1  
    fi
    export HISTCONTROL=$mySetting
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}3.3 Identify the IPv4 address and subnet of Docker${endColor}"
echo "ip addr | grep -A 2 'docker0:' | grep inet | awk '{print \$2}' | awk -F'/' '{print \$1}'"
docker_ip=$(ip addr | grep -A 2 'docker0:' | grep inet | awk '{print $2}' | awk -F'/' '{print $1}')
if [ -z "$docker_ip" ]; then
    echo -e "${red}Problem with identifying IPv4 of Docker${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}3.4 Add the Btrfs and DNS flags to the Docker startup options${endColor}"
echo 'sed -i -e "\|^DOCKER_OPTS=\"-s btrfs --dns=|d" /etc/sysconfig/docker'
sed -i -e "\|^DOCKER_OPTS=\"-s btrfs --dns=|d" /etc/sysconfig/docker         
echo 'echo "DOCKER_OPTS=\"-s btrfs --dns=$docker_ip\"" >> /etc/sysconfig/docker'
echo "DOCKER_OPTS=\"-s btrfs --dns=$docker_ip\"" >> /etc/sysconfig/docker
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with adding Btrfs and DNS flags to the Docker${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}3.5 Creating user ${user} for Control Center (serviced) management${endColor}"
echo "id -u ${user}"
id -u ${user}
if [ $? -ne 0 ]; then
    echo "adduser -M -c 'Management user for Control Center (serviced)' ${user}"
    adduser -M -c 'Management user for Control Center (serviced)' ${user}
    echo "usermod -aG wheel ${user}"
    usermod -aG wheel ${user}        
    # ubuntu
    #echo "usermod -aG sudo ${user}"
    #usermod -aG sudo ${user}
else
    echo 'User already exists'
fi 
echo -e "${green}Done${endColor}"

echo -e "${yellow}3.6 Stop and restart Docker${endColor}"
echo "systemctl stop docker && systemctl start docker"
systemctl stop docker && systemctl start docker
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with restarting of Docker${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

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
    sudo sed -i.${EXT} -e 's|^#[^H]*\(HOME=/root\)|\1|' \
     -e 's|^#[^S]*\(SERVICED_REGISTRY=\).|\11|' \
     -e 's|^#[^S]*\(SERVICED_AGENT=\).|\11|' \
     -e 's|^#[^S]*\(SERVICED_MASTER=\).|\11|' \
      /etc/default/serviced  
fi

echo -e "${yellow}3.7 Change the volume type for application data${endColor}"
echo "sed -i.$(date +\"%j-%H%M%S\") -e 's|^#[^S]*\(SERVICED_FS_TYPE=\).*$|\1btrfs|' /etc/default/serviced"
sed -i.$(date +"%j-%H%M%S") -e 's|^#[^S]*\(SERVICED_FS_TYPE=\).*$|\1btrfs|' /etc/default/serviced
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with changing of volume type${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

# rpcbind bug http://www.zenoss.org/forum/4726
echo -e "${yellow}3.8 rpcbind workaround${endColor}"
echo 'systemctl status rpcbind &>/dev/null'
systemctl status rpcbind &>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${yellow}Applying rpcbind workaround${endColor}"
    echo 'systemctl start rpcbind'
    systemctl start rpcbind
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with rpcbind start${endColor}"
        exit 1
    fi
    sed -i -e "\|^systemctl start rpcbind|d" /etc/rc.d/rc.local
    echo 'echo "systemctl start rpcbind" >> /etc/rc.d/rc.local && chmod +x /etc/rc.d/rc.local'
    echo "systemctl start rpcbind" >> /etc/rc.d/rc.local && chmod +x /etc/rc.d/rc.local
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with installing rpcbind autostart workaround${endColor}"
        exit 1  
    fi    
    echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}3.9 Start the Control Center service${endColor}"
echo "systemctl enable serviced && systemctl start serviced"
systemctl enable serviced && systemctl start serviced
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with starting of serviced${endColor}"
    exit 1
else
    echo -e "${green}Done${endColor}"
fi

# exit host installation
if [ ! -z "$MHOST" ]; then
    echo -e "${green}Control Center installation on the host completed${endColor}"
    echo -e "${green}Please visit Control Center${endColor}"
    echo -e "${green}You can check status of serviced: systemctl status serviced${endColor}"  
    exit 0
fi 

echo -e "${blue}4 ${zenoss_installation} deployement - (`date -R`)${endColor}"

echo -e "${yellow}4.1 Adding current host to the default resource pool${endColor}"
echo -e "${yellow}Please be patient, because docker image zenoss/serviced-isvcs must be downloaded before first start.${endColor}"
echo -e "${yellow}You can check progress in new console: journalctl -u serviced -f -a${endColor}"
echo -e "${yellow}Script is trying to check status every 10s. Timeout for this step is 15 minutes.${endColor}"
echo "serviced host list 2>&1"
test=$(serviced host list 2>&1)
# wait for serviced start
retry=1
while [ "$test" = "rpc: can't find service Master.GetHosts" ] || [[ "$test" =~ "could not create a client to the master: dial tcp" ]] && [ $retry -lt $retries_max ]
do
   echo $test
   echo "#${retry}: This is not a problem, because Control Centre service is not fully started, I'm trying in ${sleep_duration} seconds"
   retry=$(( $retry + 1 ))
   sleep $sleep_duration    
   test=$(serviced host list 2>&1)   
done
if [ "$test" = "no hosts found" ]; then
    echo "serviced host add $hostname:4979 default"
    serviced host add $hostname:4979 default
    if [ $? -ne 0 ]; then
        echo -e "${red}Problem with command: serviced host add $privateipv4:4979 default${endColor}"
        exit 1
    else
        echo -e "${green}Done${endColor}"
    fi
else
    echo "echo \"$test\" | wc -l"
    #test2=$(echo "$test" | grep $(uname -n) | wc -l)
    test2=$(echo "$test" | wc -l)
    if [ "$test2" -gt "1" ]; then
        echo -e "${yellow}Skipping - some host is deployed already${endColor}"
        echo -e "${green}Done${endColor}"
    else 
        echo -e "${red}Problem with adding a host - check output from test: $test${endColor}"
        exit 1
    fi  
fi

echo -e "${yellow}4.2 Deploy ${zenoss_template} application (the deployment step can take 15-30 minutes)${endColor}"
echo -e "${yellow}Please be patient, because all Zenoss docker images must be downloaded before first start.${endColor}"
echo -e "${yellow}Progress from serviced log file is presented. No timeout for this step.${endColor}"
echo "serviced template list 2>&1 | grep \"${zenoss_template}\" | awk '{print \$1}'"
TEMPLATEID=$(serviced template list 2>&1 | grep "${zenoss_template}" | awk '{print $1}')
echo 'serviced service list 2>/dev/null | wc -l'
services=$(serviced service list 2>/dev/null | wc -l)
if [ "$services" == "0" ]; then
    # log progress watching from journalctl in background
    bgjobs=$(jobs -p | wc -l)
    ((bgjobs++))
    echo "serviced template deploy $TEMPLATEID default zenoss"
    journalctl -u serviced -f -n 0 &
    serviced template deploy $TEMPLATEID default zenoss
    rc=$?
    # kill log watching
    kill %${bgjobs}
    sleep 5
    if [ $rc -ne 0 ]; then
        echo -e "${red}Problem with command: serviced template deploy $TEMPLATEID default zenoss${endColor}"
        exit 1
    fi
else
    if [ "$services" -gt "0" ]; then
        echo -e "${yellow}Skipping - some services are already deployed, check: serviced service list${endColor}"
    else
        echo -e "${red}Skipping deploying an application - check output from template test: $TEMPLATEID${endColor}"
        exit 1
    fi
fi

echo -e "${yellow}5 Tuning ${zenoss_template}${endColor}"

echo -e "${yellow}5.1 Installing the Quilt package${endColor}"
echo "Creating /tmp/quilt.txt"
cat > /tmp/quilt.txt << EOF
DESCRIPTION quilt.txt -- add Quilt to a Zenoss image
VERSION zenoss-quilt-1.0
REQUIRE_SVC
SNAPSHOT

# quilt install steps in one go - save time and space
SVC_EXEC COMMIT ${zenoss_template} yum install -y epel-release && yum makecache -y && yum install -y quilt && yum erase -y epel-release && yum clean all
EOF

echo "Syntax verification of /tmp/quilt.txt"
serviced script parse quilt.txt
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with syntax verification of /tmp/quilt.txt${endColor}"
    exit 1
fi
echo "Installing the Quilt package"
serviced script run quilt.txt --service ${zenoss_template}
if [ $? -ne 0 ]; then
    echo -e "${red}Problem with installing the Quilt package${endColor}"
    rm -rf /tmp/quilt.txt
    exit 1
fi
rm -rf /tmp/quilt.txt
echo -e "${green}Done${endColor}"

echo -e "${yellow}5.2 Installing the Percona Toolkit${endColor}"
echo " serviced service list | grep -i mariadb | awk '{print $1}' | sort -r | grep -i 'mariadb' | head -n 1"
mservice=$( serviced service list | grep -i mariadb | awk '{print $1}' | sort -r | grep -i 'mariadb' | head -n 1)
echo "serviced service start $mservice"
serviced service start $mservice
echo "serviced service run zope install-percona" 
serviced service run zope install-percona
# exit code 1 always
if [ $? -ne 1 ]; then
    echo -e "${red}Problem with installing the Percona Toolkit${endColor}"
    echo "serviced service stop $mservice"
    serviced service stop $mservice
    exit 1
fi
echo "serviced service stop $mservice"
serviced service stop $mservice

echo -e "${yellow}5.3 Configuring periodic maintenance${endColor}"
if [ -z "$MHOST" ]; then
    # cron on the CC master
    echo "Creating /etc/cron.weekly/zenoss-master-btrfs"
    cat > /etc/cron.weekly/zenoss-master-btrfs << EOF
DOCKER_PARTITION=/var/lib/docker
btrfs balance start ${DOCKER_PARTITION} && btrfs scrub start ${DOCKER_PARTITION}
 
DATA_PARTITION=/opt/serviced/var/volumes
btrfs balance start ${DATA_PARTITION} && btrfs scrub start ${DATA_PARTITION}
EOF

    chmod +x /etc/cron.weekly/zenoss-master-btrfs
else
    # cron on the CC host    
    echo "Creating /etc/cron.weekly/zenoss-pool-btrfs"
    cat > /etc/cron.weekly/zenoss-pool-btrfs << EOF
DOCKER_PARTITION=/var/lib/docker
btrfs balance start ${DOCKER_PARTITION} && btrfs scrub start ${DOCKER_PARTITION}
EOF

    chmod +x /etc/cron.weekly/zenoss-pool-btrfs
fi
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
  else
    echo -e "${green}Done${endColor}"
  fi  
fi

echo -e "${blue}5 Final overview - (`date -R`)${endColor}"
echo -e "${green}Control Center & ${zenoss_installation} installation completed${endColor}"
echo -e "${green}Set password for Control Center ${user} user: passwd ${user}${endColor}"
echo -e "${green}Please visit Control Center https://$publicipv4/ in your favorite web browser to complete setup, log in with ${user} user${endColor}"
echo -e "${green}Add following line to your hosts file:${endColor}"
echo -e "${green}$publicipv4 $hostname hbase.$hostname opentsdb.$hostname rabbitmq.$hostname zenoss5.$hostname${endColor}"
echo -e "${green}or edit /etc/default/serviced and set SERVICED_VHOST_ALIASES to your FQDN${endColor}"
# selinux test
output=$(id)
substring="context="
if [ "$output" != "${output%$substring*}" ]; then
  echo -e "${red}Please also reboot machine, because SELINUX is still active!${endColor}"
fi
echo -e "Install guide: ${install_doc}"
echo -e "${blue}Credit: www.jangaraj.com${endColor}"
