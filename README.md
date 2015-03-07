Zenoss Core 5 autodeploy script
===============================
Auto-deployment script for Zenoss Core 5 on CentOS 7.x or Red Hat Enterprise 
Linux 7.x. Ubuntu is not supported at the moment. A 64-bit build is required.

The script included in this directory will automatically deploy Zenoss Core 5 
and Control Center for you. 

```
# cd /tmp
# chmod +x core-autodeploy.sh
# ./core-autodeploy.sh
```

The script will take several minutes (around 15-30) to complete. When done, 
you should be able to visit Control Center in a web browser to start 
Zenoss Core 5 application.

Script requires mounted directories:

```
/var/lib/docker 
/opt/serviced/var
/opt/serviced/var/volumes
/opt/serviced/var/backups
```

Or you can pass a block device for formatting and mounting of required filesystem. 
Confirmation is needed before formatting. E.g.:

```
# ./core-autodeploy.sh -d </var/lib/docker block device> -s </opt/serviced/var block device>
 -v </opt/serviced/var/volumes block device> -b </opt/serviced/var/backups block device>

# ./core-autodeploy.sh -d /dev/sdb1 -s /dev/sdb2 -v /dev/sdc1 -b /dev/sdd1
```

Example
=======

```
[root@localhost ~]# ./core-autodeploy.sh
Autodeploy script 2015-03-01 (beta) for Control Center master host and Zenoss 5 Core
Doc: http://wiki.zenoss.org/download/core/docs/Zenoss_Core_Installation_Guide_r5.0.0_d1051.15.055.pdf
Requirements:
Min number of available CPUs: 4
Min size of available RAM:    20GB
These filesystems must be mounted with correct type and size:
Filesystem                  Type        Min size
/                           xfs         30GB
/var/lib/docker             btrfs       30GB
/opt/serviced/var           xfs         30GB
/opt/serviced/var/volumes   btrfs       1GB
/opt/serviced/var/backups   xfs         1GB
1 Checks
1.1 Root permission check
Done
1.2 Architecture check
Done
1.3 OS version check
Done
1.4 CPU check
Done
1.5 RAM check
Done
1.6 / filesystem check
Done
1.7 /var/lib/docker filesystem check
Done
1.8 /opt/serviced/var filesystem check
Done
1.9 /opt/serviced/var/volumes filesystem check
Done
1.10 /opt/serviced/var/backups filesystem check
Done
2 Preparing the master host
2.1 IP configurations
Hostname: ip-192-168-72-131
192.168.72.131 ip-192-168-72-131
IPv4: 192.168.72.131
Done
2.2 Disable the firewall
systemctl stop firewalld && systemctl disable firewalld
Done
2.3 Enable persistent storage for log files
mkdir -p /var/log/journal && systemctl restart systemd-journald
Done
2.4 Disable selinux
Done
2.5 Download and install the Zenoss repository package
rpm -ivh http://get.zenoss.io/yum/zenoss-repo-1-1.x86_64.rpm
Retrieving http://get.zenoss.io/yum/zenoss-repo-1-1.x86_64.rpm
Preparing...                          ########################################
        package zenoss-repo-1-1.x86_64 is already installed
Done
2.6 Install and start the dnsmasq package
yum install -y dnsmasq && systemctl enable dnsmasq && systemctl start dnsmasq
Loaded plugins: fastestmirror
Loading mirror speeds from cached hostfile
 * base: mirror.vorboss.net
 * epel: mirror.vorboss.net
 * extras: repo.bigstepcloud.com
 * updates: repo.bigstepcloud.com
Package dnsmasq-2.66-12.el7.x86_64 already installed and latest version
Nothing to do
Done
2.7 Install and start the ntp package
yum install -y ntp && systemctl enable ntpd
Loaded plugins: fastestmirror
Loading mirror speeds from cached hostfile
 * base: mirror.vorboss.net
 * epel: mirror.vorboss.net
 * extras: repo.bigstepcloud.com
 * updates: repo.bigstepcloud.com
Package ntp-4.2.6p5-19.el7.centos.x86_64 already installed and latest version
Nothing to do
Done
2.8 ntpd autostart workaround
echo "systemctl start ntpd" >> /etc/rc.d/rc.local && chmod +x /etc/rc.d/rc.local
Done
2.9 ntpd start
systemctl start ntpd
Done
3 Installing on the master host
3.1 Install Control Center, Zenoss Core, and Docker
yum --enablerepo=zenoss-stable install -y zenoss-core-service
Loaded plugins: fastestmirror
Loading mirror speeds from cached hostfile
 * base: mirror.vorboss.net
 * epel: mirror.vorboss.net
 * extras: repo.bigstepcloud.com
 * updates: repo.bigstepcloud.com
Package zenoss-core-service-5.0.0-1.noarch already installed and latest version
Nothing to do
Done
3.2 Start Docker
systemctl start docker
Done
3.3 Identify the IPv4 address and subnet of Docker
ip addr | grep -A 2 'docker0:' | grep inet | awk '{print $2}' | awk -F'/' '{print $1}'
Done
3.4 Add the Btrfs and DNS flags to the Docker startup options
sed -i -e "\|^DOCKER_OPTS=\"-s btrfs --dns=|d" /etc/sysconfig/docker
echo "DOCKER_OPTS=\"-s btrfs --dns=$docker_ip\"" >> /etc/sysconfig/docker
Done
3.5 Creating user serviceman for Control Center (serviced) management
id -u serviceman
1003
User already exists
Done
3.6 Stop and restart Docker
systemctl stop docker && systemctl start docker
Done
3.7 Change the volume type for application data
sed -i."059-192013" -e 's|^#[^S]*\(SERVICED_FS_TYPE=\).*$|\1btrfs|' /etc/default/serviced
Done
3.8 Start the Control Center service
systemctl start serviced
Done
4 Zenoss Core 5 deployement
4.1 Adding current host to the default resource pool
serviced host list 2>&1
could not create a client to the master: dial tcp 192.168.72.131:4979: connection refused
Retry #1: Control Service is not fully started, I'm trying in next 10seconds
rpc: can't find service Master.GetHosts
Retry #2: Control Service is not fully started, I'm trying in next 10seconds
rpc: can't find service Master.GetHosts
Retry #3: Control Service is not fully started, I'm trying in next 10seconds
rpc: can't find service Master.GetHosts
Retry #4: Control Service is not fully started, I'm trying in next 10seconds
rpc: can't find service Master.GetHosts
Retry #5: Control Service is not fully started, I'm trying in next 10seconds
echo "ID                POOL            NAME                    ADDR            RPCPORT         CORES   MEM             NETWORK
007f0100        default         localhost.localdomain   192.168.72.131  4979            4       8189747200      172.17.0.0/255.255.0.0" | grep $(uname -n) | wc -l
Skipping - host is deployed already
Done
4.2 Deploy Zenoss.core application (the deployment step can take 15-30 minutes)
You can monitor progress by entering the following command in another console: journalctl -u serviced -f
serviced template list 2>&1 | grep 'Zenoss.core' | awk '{print $1}'
serviced service list 2>/dev/null | wc -l
Skipping - some services are already deployed, check: serviced service list
5 Final overview
Control Center & Zenoss Core 5 installation completed
Set password for Control Center serviceman user: passwd serviceman
Please visit Control Center https://192.168.72.131/ in your favorite web browser to complete setup, log in with serviceman user
Add following line to your hosts file:
192.168.72.131 ip-192-168-72-131 hbase.ip-192-168-72-131 opentsdb.ip-192-168-72-131 rabbitmq.ip-192-168-72-131 zenoss5.ip-192-168-72-131

Credit: www.jangaraj.com
```

Author
======
 
[Devops Monitoring zExpert](http://www.jangaraj.com), who loves monitoring systems, which start with letter Z. Those are Zabbix and Zenoss. [LinkedIn] (http://uk.linkedin.com/in/jangaraj/).
