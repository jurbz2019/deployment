# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

VIEWER="CodeDX"
viewer="codedx"
MYSQLPWFILE="/root/.mysql.pw"
TOMCATVERSION="/opt/apache-tomcat-8.5.28"
TOMCATSERVICE="tomcat"
TOMCATDIR="/opt/$TOMCATSERVICE"
TOMCATLOG="$TOMCATDIR/logs/catalina.out"
RUNOUT="/mnt/out/run.out"
RUNEPOCH="/mnt/out/run.epoch"
EVENTOUT="/dev/ttyS1"
VMIPOUT="/dev/ttyS2"
shutdown_on_error=1

# function to echo events to RUNOUT and EVENTOUT
sequence=10
record_event () {
	event_name=$1
	event_message=$2
	echo "`date +"%Y/%m/%d %H:%M:%S"`: $sequence $event_name $event_message" >> $RUNOUT 2>&1
	echo "$event_name" > $EVENTOUT
	((sequence+=1))
}

record_event RUNSHSTART "Starting $VIEWER viewer via run.sh"
echo `date +%s` > $RUNEPOCH

# start in /mnt/in - the viewer VM input directory
cd /mnt/in

# check for ip connectivity
for i in {1..10}
do
	VMIP=$(ip route get 1 | awk '{print $7; exit}')
	# this will implicitly wait for 1 second between each of 3 pings
	ping -c 3 $VMIP
	if [ $? == 0 ]
	then
		break
	fi
done
echo "$VMIP `hostname`" >> /etc/hosts
ping -c 3 `hostname`
if [ $? != 0 ]
then
	record_event NOIP "ERROR: NO IP ADDRESS"
	if [ $shutdown_on_error -eq 1 ]
	then
		record_event NOIPSHUTDOWN "Shutting down $VIEWER viewer via run.sh"
		shutdown -h now
		exit
	fi
fi
echo $VMIP > $VMIPOUT

# set viewer database backup as shutdown service
cp /mnt/in/swamp-shutdown-service /etc/init.d/.
chmod +x /etc/init.d/swamp-shutdown-service
chkconfig --add swamp-shutdown-service
service swamp-shutdown-service start
chmod +x /mnt/in/backup_viewerdb.sh

# set ownership of mysql
chown -R mysql:mysql /var/lib/mysql/* >> $RUNOUT 2>&1
sed -i -e'/\[mysqld\]/c[mysqld]\nlower_case_table_names=2' /etc/my.cnf.d/server.cnf >> $RUNOUT 2>&1

# start mysql service
record_event MYSQLSTART "Starting mysql service"
service mysql start >> $RUNOUT 2>&1
if [ $? -ne 0 ]
then
	record_event MYSQLFAIL "Service mysql failed to start"
	service mysql status >> $RUNOUT 2>&1
	if [ $shutdown_on_error -eq 1 ]
	then
		record_event MYSQLSHUTDOWN "Shutting down $VIEWER viewer via run.sh"
		shutdown -h now
		exit
	fi
else
	record_event MYSQLRUN "Service mysql running"
	echo "" >> $RUNOUT 2>&1
fi

# restore mysql database from scripts if extant 
read -r mysqlpw < $MYSQLPWFILE
# initialize mysql database
if [ -r emptydb-mysql-${viewer}.sql ]
then
	record_event MYSQLEMPTY "Restoring $VIEWER viewer database from emptydb-mysql-${viewer}.sql"
	mysql --user='root' --password="$mysqlpw" mysql < emptydb-mysql-${viewer}.sql >> $RUNOUT 2>&1
	# reset root password
	mysqladmin --user='root' --password="$mysqlpw" flush-privileges
	mysqladmin --user='root' --password='m@r1ad8l3tm31n' password $mysqlpw
	mysqladmin --user='root' --password="$mysqlpw" flush-privileges
	echo "" >> $RUNOUT 2>&1
fi
# flush priveleges
if [ -r flushprivs.sql ]
then
	record_event MYSQLGRANT "Granting privileges for $VIEWER viewer database from flushprivs.sql"
	mysql --user='root' --password="$mysqlpw" mysql < flushprivs.sql >> $RUNOUT 2>&1
	echo "" >> $RUNOUT 2>&1
fi
# drop and create viewer database
if [ -r resetdb-${viewer}.sql ]
then
	record_event MYSQLDROP "Dropping $VIEWER viewer database from resetdb-${viewer}.sql"
	mysql --user='root' --password="$mysqlpw" < resetdb-${viewer}.sql >> $RUNOUT 2>&1
	echo "" >> $RUNOUT 2>&1
fi
# if a previously saved user database exists load it, 
if [ -r ${viewer}.sql ]
then
	record_event USERDB "Restoring $VIEWER user database from ${viewer}.sql"
	mysql --user='root' --password="$mysqlpw" ${viewer} < ${viewer}.sql >> $RUNOUT 2>&1
	echo "" >> $RUNOUT 2>&1
# otherwise load empty database for this version of viewer
elif [ -r emptydb-${viewer}.sql ]
then
	record_event EMPTYDB "Restoring $VIEWER viewer database from emptydb-${viewer}.sql"
	mysql --user='root' --password="$mysqlpw" ${viewer} < emptydb-${viewer}.sql >> $RUNOUT 2>&1
	echo "" >> $RUNOUT 2>&1
fi

# unbundle ${viewer}_config if extant to new location outside of webapps
# setup codedx.props and logback.xml in new location outside of webapps
record_event CREATEPROXY "Creating /var/lib/${viewer}/$PROJECT"
mkdir -p /var/lib/${viewer}/$PROJECT >> $RUNOUT 2>&1
if [ -r ${viewer}_config.tar ]
then
	record_event CONFIG "Restoring $VIEWER config from ${viewer}_config.tar"
    tar -C /var/lib/${viewer}/$PROJECT -xf ${viewer}_config.tar
else
	record_event EMPTYCONFIG "Creating empty $VIEWER config"
	mkdir -p /var/lib/${viewer}/$PROJECT/config >> $RUNOUT 2>&1
fi
record_event PROPERTIES "Copying ${viewer}.props and logback.xml to $VIEWER config"
cp ${viewer}.props /var/lib/${viewer}/$PROJECT/config >> $RUNOUT 2>&1
cp logback.xml /var/lib/${viewer}/$PROJECT/config >> $RUNOUT 2>&1

# setup tomcat version
rm -f $TOMCATDIR
ln -s $TOMCATVERSION $TOMCATDIR

# setup VIEWER proxy directory and unzip VIEWER.war
mkdir -p $TOMCATDIR/webapps/$PROJECT >> $RUNOUT 2>&1
record_event WARFILE "Restoring $VIEWER webapp from ${viewer}.war"
unzip -d $TOMCATDIR/webapps/$PROJECT ${viewer}.war
# copy version file to config directory
cp $TOMCATDIR/webapps/$PROJECT/WEB-INF/classes/version.properties /var/lib/codedx/$PROJECT/config

# indicate that ${viewer} should skip initial installation
touch /var/lib/codedx/$PROJECT/config/.installation >> $RUNOUT 2>&1

# tell tomcat where ${viewer}.props resides
echo "${viewer}.appdata=\/var\/lib\/${viewer}\/$PROJECT\/config/" >> $TOMCATDIR/conf/catalina.properties

# adjust file system permissions
chown -R tomcat:tomcat $TOMCATDIR >> $RUNOUT 2>&1

# clear tomcat log file
/bin/rm -f $TOMCATLOG >> $RUNOUT 2>&1
echo "" >> $RUNOUT 2>&1

# start tomcat service
record_event TOMCATSTART "Starting tomcat service"
service $TOMCATSERVICE start >> $RUNOUT 2>&1
tomcat_started=0
for i in {1..10}
do
	result=$(service $TOMCATSERVICE status)
	if [[ $result == *"running with pid:"* ]]
	then
		tomcat_started=1
		break
	fi
	sleep 1
done
if [ $tomcat_started -eq 0 ]
then
	record_event TOMCATFAIL "Service tomcat failed to start"
	service $TOMCATSERVICE status >> $RUNOUT 2>&1
	if [ $shutdown_on_error -eq 1 ]
	then
		record_event TOMCATSHUTDOWN "Shutting down $VIEWER viewer via run.sh"
		shutdown -h now
		exit
	fi
else
	record_event TOMCATRUN "Service tomcat running"
	echo "" >> $RUNOUT 2>&1
fi

# check for server startup
SERVER_READY="Server startup in .* ms"
grep -q "$SERVER_READY" $TOMCATLOG
RET=$?
while [ $RET -ne 0 ]
do
    sleep 2
    grep -q "$SERVER_READY" $TOMCATLOG
    RET=$?
done

# echo contents of tomcat log file
echo "`date +"%Y/%m/%d %H:%M:%S"`: Contents of $TOMCATLOG" >> $RUNOUT 2>&1
cat $TOMCATLOG >>  $RUNOUT 2>&1
echo "" >> $RUNOUT 2>&1

# echo contents of VIEWER webapps directory
echo "`date +"%Y/%m/%d %H:%M:%S"`: Contents of $TOMCATDIR/webapps" >> $RUNOUT 2>&1
ls -lart $TOMCATDIR/webapps >> $RUNOUT 2>&1

# start the timeout script via cron and check timeout every CHECKTIMEOUT_FREQUENCY minutes
record_event TIMERSTART "Starting checktimeout"
chmod +x /mnt/in/checktimeout
chmod +x /mnt/in/checktimeout.pl
echo "*/$CHECKTIMEOUT_FREQUENCY * * * * root /mnt/in/checktimeout" >> /etc/crontab

# viewer is up
echo "" >> $RUNOUT 2>&1
record_event VIEWERUP "$VIEWER viewer is UP"

# Tell anyone listening our ipaddress
echo BEGIN ifconfig >> $RUNOUT 2>&1
ip -o -4 address show dev eth0 >> $RUNOUT 2>&1
echo END ifconfig >> $RUNOUT 2>&1

