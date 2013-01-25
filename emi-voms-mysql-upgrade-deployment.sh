#!/bin/bash
 
# This script execute an upgrade deployment of the emi-voms-mysql package.
#
#
set -e

emi_release_package="http://emisoft.web.cern.ch/emisoft/dist/EMI/2/sl6/x86_64/base/emi-release-2.0.0-1.sl6.noarch.rpm"

emi_repo=$DEFAULT_EMI_REPO
voms_repo=$DEFAULT_VOMS_REPO

emi_repo_filename="/etc/yum.repos.d/test_emi.repo"
voms_repo_filename="/etc/yum.repos.d/test_voms.repo"

populate_vo_script_url="tbd"

hostname=$(hostname -f)
vo=emi3
mail_from=andrea.ceccanti@cnaf.infn.it
tomcat=tomcat6

[ $# -eq 1 ] && emi_repo=$1
[ $# -eq 2 ] && voms_repo=$2

[ -z "$emi_repo" ]  && ( echo "Usage: $0 EMI_REPO_URL [VOMS_REPO_URL]"; exit 1 )

execute() {
  echo "[root@`hostname` ~]# $1"
  eval "$1" || ( echo "Deployment failed"; exit 1 )
}
 
execute "mkdir emi-release-package"
execute "wget -P emi-release-package $emi_release_package"
xecute "yum -y localinstall emi-release-package/*.rpm"
execute "yum clean all"
execute "yum -y install emi-voms-mysql"
execute "yum -y install xml-commons-apis"
execute "service mysqld start"
execute "sleep 5"
execute "/usr/bin/mysqladmin -u root password pwd"
execute "/usr/bin/mysqladmin -u root -h $hostname password pwd"
execute "mkdir siteinfo"

# configure voms using yaim
execute "cat > siteinfo/site-info.def << EOF
MYSQL_PASSWORD="pwd"
SITE_NAME="voms-certification.cnaf.infn.it"
VOS="$vo"
VOMS_HOST=$hostname
VOMS_DB_HOST='localhost'
VO_TESTVO_VOMS_PORT=15000
VO_TESTVO_VOMS_DB_USER=${vo}_vo
VO_TESTVO_VOMS_DB_PASS=pwd
VO_TESTVO_VOMS_DB_NAME=voms_${vo}
VOMS_ADMIN_SMTP_HOST=postino.cnaf.infn.it
VOMS_ADMIN_MAIL=andrea.ceccanti@cnaf.infn.it
EOF"

execute '/opt/glite/yaim/bin/yaim -c -s siteinfo/site-info.def -n VOMS'
# wait a while
execute 'sleep 10'
 
# check voms-admin can list groups
execute "voms-admin --vo $vo list-groups"
 
# populate vo
execute "wget --no-check-certificate $populate_vo_script"
execute "sh populate-vo.sh $vo"

# Stop the services
execute "service voms stop"
execute "service voms-admin stop"
execute "service $tomcat stop"

# Remove emi-release package
execute "yum -y remove emi-release"

# Download EMI 3 repos & VOMS repos
execute "wget -q $emi_repo -O $emi_repo_filename"

if [ ! -z "$voms_repo" ]; then
    execute "wget -q $voms_repo -O $voms_repo_filename"
    execute "echo >> $voms_repo_filename; echo 'priority=1' >> $voms_repo_filename"
fi

# clean yum
execute "yum clean all"

execute "yum -y install emi-release"
execute "yum -y update"
execute "yum -y remove $tomcat"

execute "cat > reconfigure-voms.sh << EOF
#!/bin/bash
hostname=$(hostname -f)
voms-configure install --vo $vo \
--core-port 15000 \
--admin-port 16000 \
--hostname $hostname \
--dbusername ${vo}_vo \
--dbpassword pwd \
--dbname voms_${vo} \
--mail-from $mail_from \
--smtp-host postino.cnaf.infn.it
EOF"

execute "sh reconfigure-voms.sh"
execute "service voms-admin start"
execute "service voms start"

execute "sleep 20"

# Install clients
execute "yum -y install voms-clients3"

# Configure lsc and vomses
if [ ! -d "/etc/vomses" ]; then
        execute "mkdir /etc/vomses"
fi

# Install voms clients
execute "yum -y install voms-clients3"

# Setup certificate for voms-proxy-init test
execute "mkdir -p .globus"
execute "cp /usr/share/igi-test-ca/test0.cert.pem .globus/usercert.pem"
execute "cp /usr/share/igi-test-ca/test0.key.pem .globus/userkey.pem"
execute "chmod 600 .globus/usercert.pem"
execute "chmod 400 .globus/userkey.pem"

# Setup vomsdir & vomses
# Configure lsc and vomses
execute "mkdir /etc/vomses"
execute "cp /etc/voms-admin/$vo/vomses /etc/vomses/$vo"
execute "mkdir /etc/grid-security/vomsdir/$vo"
execute "cp /etc/voms-admin/$vo/lsc /etc/grid-security/vomsdir/$vo/$hostname.lsc"

# VOMS proxy init test
execute "echo 'pass' | voms-proxy-init -voms $vo --pwstdin --debug"

echo "VOMS succesfully upgraded!"
