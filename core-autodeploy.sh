#!/bin/bash

# Script for single-host Control Center and Zenoss Core 5 deployement
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
servicedbackups_fs_type="btrfs"
g2k=1048576
user="serviceman"
version="2015-03-12"
retries_max=90
sleep_duration=10
install_doc="http://wiki.zenoss.org/download/core/docs/Zenoss_Core_Installation_Guide_r5.0.0_d1051.15.055.pdf"
    
green='\e[0;32m'
yellow='\e[0;33m'
red='\e[0;31m'
blue='\e[0;34m'
endColor='\e[0m'

echo -e "${yellow}Autodeploy script ${version} for Control Center master host and Zenoss 5 Core${endColor}"
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
          
while getopts "d:s:v:b:" arg; do
  case $arg in
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
              else
                  echo "mkfs -t ${rfs} -f ${dev}"
                  mkfs -t ${rfs} -f ${dev}              
              fi
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with formating ${dev}${endColor}"
                exit 1
              fi
              # fstab
              echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
              sed -i -e "\|^$dev|d" /etc/fstab                  
              echo "echo \"${dev} ${path} ${rfs} rw,noatime,nodatacow 0 0\" >> /etc/fstab"
              echo "${dev} ${path} ${rfs} rw,noatime,nodatacow 0 0" >> /etc/fstab
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
              else
                  echo "mkfs -t ${rfs} -f ${dev}"
                  mkfs -t ${rfs} -f ${dev}              
              fi
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with formating ${dev}${endColor}"
                exit 1
              fi
              # fstab
              echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
              sed -i -e "\|^$dev|d" /etc/fstab                  
              echo "echo \"${dev} ${path} ${rfs} rw,noatime 0 0\" >> /etc/fstab"
              echo "${dev} ${path} ${rfs} rw,noatime 0 0" >> /etc/fstab
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
              else
                  echo "mkfs -t ${rfs} -f ${dev}"
                  mkfs -t ${rfs} -f ${dev}              
              fi
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with formating ${dev}${endColor}"
                exit 1
              fi
              # fstab
              echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
              sed -i -e "\|^$dev|d" /etc/fstab                  
              echo "echo \"${dev} ${path} ${rfs} rw,noatime,nodatacow 0 0\" >> /etc/fstab"
              echo "${dev} ${path} ${rfs} rw,noatime,nodatacow 0 0" >> /etc/fstab
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
              else
                  echo "mkfs -t ${rfs} -f ${dev}"
                  mkfs -t ${rfs} -f ${dev}              
              fi
              if [ $? -ne 0 ]; then
                echo -e "${red}Problem with formating ${dev}${endColor}"
                exit 1
              fi
              # fstab
              echo "sed -i -e \"\|^$dev|d\" /etc/fstab"
              sed -i -e "\|^$dev|d" /etc/fstab                  
              echo "echo \"${dev} ${path} ${rfs} rw,noatime,nodatacow 0 0\" >> /etc/fstab"
              echo "${dev} ${path} ${rfs} rw,noatime,nodatacow 0 0" >> /etc/fstab
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
    echo -e "${red}/ filesystem size is less than required ${root_fs_min_size}GB${endColor}"
    exit 1    
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
    echo -e "${red}/var/lib/docker filesystem size is less than required ${docker_fs_min_size}GB${endColor}"
    exit 1    
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
    echo -e "${red}/opt/serviced/var filesystem size is less than required ${serviced_fs_min_size}GB${endColor}"
    exit 1    
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}1.9 /opt/serviced/var/volumes filesystem check${endColor}"
fs=$(df -T | grep ' \/opt\/serviced\/var\/volumes$' | awk '{print $2}')
if [ -z "$fs" ]; then
    echo -e "${red}/opt/serviced/var/volumes filesystem was not detected${endColor}"
    exit 1
fi
if [ "$fs" != "$servicedvolumes_fs_type" ]; then
    echo -e "${red}${fs} /opt/serviced/var/volumes filesystem detected, but ${servicedvolumes_fs_type} is required${endColor}"
    exit 1    
fi
ss=$(df -T | grep ' \/opt\/serviced\/var\/volumes$' | awk '{print $3}')
mss=$(($servicedvolumes_fs_min_size * $g2k))
if [ $ss -lt $mss ]; then
    echo -e "${red}/opt/serviced/var/volumes filesystem size is less than required ${servicedvolumes_fs_min_size}GB${endColor}"
    exit 1    
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}1.10 /opt/serviced/var/backups filesystem check${endColor}"
fs=$(df -T | grep ' \/opt\/serviced\/var\/backups$' | awk '{print $2}')
if [ -z "$fs" ]; then
    echo -e "${red}/opt/serviced/var/backups filesystem was not detected${endColor}"
    exit 1
fi
if [ "$fs" != "$servicedbackups_fs_type" ]; then
    echo -e "${red}${fs} /opt/serviced/var/backups filesystem detected, but ${servicedbackups_fs_type} is required${endColor}"
    exit 1    
fi
ss=$(df -T | grep ' \/opt\/serviced\/var\/backups$' | awk '{print $3}')
mss=$(($servicedbackups_fs_min_size * $g2k))
if [ $ss -lt $mss ]; then
    echo -e "${red}/opt/serviced/var/backups filesystem size is less than required ${servicedbackups_fs_min_size}GB${endColor}"
    exit 1    
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${blue}2 Preparing the master host - (`date -R`)${endColor}"

echo -e "${yellow}2.1 IP configurations${endColor}"
# ifconfig is not available in min installation - ip addr show used
privateipv4=$(ip addr show | grep -A 1 'eth0' | grep inet | awk '{print $2}' | awk -F'/' '{print $1}')
privateipv42=$(ip addr show | grep -A 1 'eno' | grep inet | awk '{print $2}' | awk -F'/' '{print $1}')
# test of empty - ask input from user
if [ -z "$privateipv4" ] && [ -z "$privateipv42" ]; then
    echo "Network interface auto detection failed. Available interfaces in your system:"
    ls /sys/class/net | grep -v lo
    echo "Please write interface, which you want to use for deployement, e.g. eth1 or ens160:"
    read interface
    privateipv4=$(ip addr show | grep -A 1 $interface | grep inet | awk '{print $2}' | awk -F'/' '{print $1}')
fi
# AWS/HP Cloud public IPv4 address
publicipv4=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 | tr '\n' ' ')
if [[ ! $publicipv4 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    if [ -z "$privateipv4" ]; then
        publicipv4=$privateipv42
        privateipv4=$privateipv42
    else
        publicipv4=$privateipv4
    fi
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
echo "IPv4: $publicipv4"
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
    echo -e "${green}Done${endColor}"
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
echo 'yum --enablerepo=zenoss-stable install -y zenoss-core-service'
yum --enablerepo=zenoss-stable install -y zenoss-core-service
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

echo -e "${yellow}3.7 Change the volume type for application data${endColor}"
echo "sed -i.$(date +\"%j-%H%M%S\") -e 's|^#[^S]*\(SERVICED_FS_TYPE=\).*$|\1btrfs|' /etc/default/serviced"
sed -i.$(date +"%j-%H%M%S") -e 's|^#[^S]*\(SERVICED_FS_TYPE=\).*$|\1btrfs|' /etc/default/serviced
if [ $? -ne 0 ]; then
  echo -e "${red}Problem with changing of volume type${endColor}"
  exit 1
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${yellow}3.8 Start the Control Center service${endColor}"
echo "systemctl enable serviced && systemctl start serviced"
systemctl enable serviced && systemctl start serviced
if [ $? -ne 0 ]; then
  echo -e "${red}Problem with starting of serviced${endColor}"
  exit 1
else
  echo -e "${green}Done${endColor}"
fi

echo -e "${blue}4 Zenoss Core 5 deployement - (`date -R`)${endColor}"

echo -e "${yellow}4.1 Adding current host to the default resource pool${endColor}"
echo -e "${yellow}Please be patient, because docker image zenoss/serviced-isvcs must be downloaded before first start${endColor}"
echo -e "${yellow}Script is trying to check status every 10s. Time limit is 15 minutes.${endColor}"
echo "serviced host list 2>&1"
test=$(serviced host list 2>&1)
# wait for serviced start
retry=1
while [ "$test" = "rpc: can't find service Master.GetHosts" ] || [[ "$test" =~ "could not create a client to the master: dial tcp" ]] && [ $retry -lt $retries_max ]
do
   echo $test
   echo "Retry #${retry}: Control Service is not fully started, I'm trying in next ${sleep_duration} seconds"
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

echo -e "${yellow}4.2 Deploy Zenoss.core application (the deployment step can take 15-30 minutes)${endColor}"
echo "serviced template list 2>&1 | grep 'Zenoss.core' | awk '{print \$1}'"
TEMPLATEID=$(serviced template list 2>&1 | grep 'Zenoss.core' | awk '{print $1}')
echo 'serviced service list 2>/dev/null | wc -l'
services=$(serviced service list 2>/dev/null | wc -l)                      
if [ "$TEMPLATEID" == "05d70f0fb778ff5d1b9461dca75fa4bb" ] && [ "$services" == "0" ]; then
  # log progress watching from journalctl in background
  bgjobs=$(jobs -p | wc -l)
  ((bgjobs++))
  echo "serviced template deploy $TEMPLATEID default zenoss"
  journalctl -u serviced -f &
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
    echo -e "${red}Skipping deloying an application - check output from template test: $TEMPLATEID${endColor}"
    exit 1
  fi
fi

echo -e "${blue}5 Final overview - (`date -R`)${endColor}"
echo -e "${green}Control Center & Zenoss Core 5 installation completed${endColor}"
echo -e "${green}Set password for Control Center ${user} user: passwd ${user}${endColor}"
echo -e "${green}Please visit Control Center https://$publicipv4/ in your favorite web browser to complete setup, log in with ${user} user${endColor}"
echo -e "${green}Add following line to your hosts file:${endColor}"
echo -e "${green}$publicipv4 $hostname hbase.$hostname opentsdb.$hostname rabbitmq.$hostname zenoss5.$hostname${endColor}"
echo -e "${green}or edit /etc/default/serviced and set SERVICED_VHOST_ALIASES to your FQDN${endColor}"
echo -e "Install guide: ${install_doc}"
echo -e "${blue}Credit: www.jangaraj.com${endColor}"
