#!/bin/bash

#set -eo pipefail
#shopt -s nullglob

file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

docker_env () {
file_env 'hostname'
file_env 'db_host'
file_env 'db_user'
file_env 'db_password'
file_env 'db_name'
file_env 'mysql_data_dir'
file_env 'backup_folder'
file_env 'backup_type' # options: full snapshot/backup of all dbs: "full" Incremental snapshot of bin-logs: "inc" Sync bin-logs to s3 space: "sync"
file_env 's3_access_key'
file_env 's3_access_secret'
file_env 's3_endpoint'  # s3cfg host_base - nyc3.digitaloceanspaces.com
file_env 's3_bucket' # s3cfg host_bucket
file_env 's3_bucket_location' # example: US
file_env 's3_bucket_folder'
file_env 'full_freq'
file_env 'sync_freq'


export hostname
export db_host
export db_user
export db_password
export db_name
export mysql_data_dir
export backup_folder
export backup_type
export s3_access_key
export s3_access_secret
export s3_endpoint
export s3_bucket
export s3_bucket_location
export s3_bucket_folder
export full_freq
export sync_freq
}

backup_opt () {
type=`echo $backup_type |tr '[:upper:]' '[:lower:]'`
if [ $type == full ]; then
	full_backup

elif [ $type == inc ]; then
	inc_backup

elif [ $type == sync ]; then
	sync_backup

else

	echo "Invalid Backup Option $backup_type, please use one of the following options: full inc sync."
        sleep 60
        main
	#exit 1
fi
}

full_backup () {
sql_conn_test
if [ "$?" == "0" ]; then
	mysqldump -h $db_host -u$db_user -p$db_password --single-transaction --events --routines --triggers --all-databases > $backup_dir/full_backup-$time.sql
        gzip $backup_dir/full_backup-$time.sql
	echo "Backup Successfully Created:"
	ls -ahl $backup_dir/full_backup-$time.sql.gz
	echo "Uploading backup -> s3://$s3_bucket$s3_bucket_folder/$year/$month/$day/$hostname/full/"
	s3cmd put --disable-multipart $backup_dir/full_backup-$time.sql.gz s3://$s3_bucket$s3_bucket_folder/$year/$month/$day/$hostname/full/
        echo "Validating Backup"
        validate_full_backup

else
	echo "sql_conn_test exited with code $?"
        echo "sleeping 60 seconds and restarting script."
        sleep 60
        main
	#exit 1
fi
}

validate_full_backup () {
if [ ! -d $backup_dir/s3/ ]; then
        mkdir $backup_dir/s3/
        echo "creating $backup_dir/s3/"
else
        echo "$backup_dir/s3/ exists"
        ls $backup_dir
fi

if [ ! -d /sqlbakvalidation/error ]; then
	mkdir -p /sqlbakvalidation/error/
        mkdir -p /sqlbakvalidation/valid/
        echo "creating /sqlbakvalidation"
else
        echo "/sqlbakvalidation exists"
        #echo "ls /sqlbakvalidation/error/"
        #ls /sqlbakvalidation/error/
        #echo "ls /sqlbakvalidation/valid/"
        #ls /sqlbakvalidation/valid/
fi

cd $backup_dir/s3/
s3cmd get s3://$s3_bucket$s3_bucket_folder/$year/$month/$day/$hostname/full/full_backup-$time.sql.gz

if [[ $(diff $backup_dir/full_backup-$time.sql.gz $backup_dir/s3/full_backup-$time.sql.gz) ]]; then
        echo "diff $backup_dir/full_backup-$time.sql.gz $backup_dir/s3/full_backup-$time.sql.gz"
        diff $backup_dir/full_backup-$time.sql.gz $backup_dir/s3/full_backup-$time.sql.gz
	echo "ERROR! Files Differ"  >> /sqlbakvalidation/error/full_backup-$time.sql.log
	ls -la $backup_dir/full_backup-$time.sql.gz >> /sqlbakvalidation/error/full_backup-$time.sql.log
	ls -la $backup_dir/s3/full_backup-$time.sql.gz >> /sqlbakvalidation/error/full_backup-$time.sql.log
        #s3cmd put $backup_dir/full_backup-$time.sql.gz s3://$s3_bucket$s3_bucket_folder/$year/$month/$day/$hostname/full/
        #echo "Retrying upload to s3://$s3_bucket$s3_bucket_folder/$year/$month/$day/$hostname/full/full_backup-$time.sql.gz"
        echo "ERROR! Backup Failed!!! Restarting Backup Script!"
        main
else
        echo "diff $backup_dir/full_backup-$time.sql.gz $backup_dir/s3/full_backup-$time.sql.gz"
        diff $backup_dir/full_backup-$time.sql.gz $backup_dir/s3/full_backup-$time.sql.gz
        echo "VALID! No Difference between local and s3."  >> /sqlbakvalidation/valid/full_backup-$time.sql.log
        ls -la $backup_dir/full_backup-$time.sql.gz >> /sqlbakvalidation/valid/full_backup-$time.sql.log
        ls -la $backup_dir/s3/full_backup-$time.sql.gz >> /sqlbakvalidation/valid/full_backup-$time.sql.log
        echo "SUCCESS! Upload to s3://$s3_bucket$s3_bucket_folder/$year/$month/$day/$hostname/full/full_backup-$time.sql.gz Complete."
	full_backup_freq
	#echo "sleeping for 10800s(3 hours) and restarting script."
        #timeout = $((3600 * 3))
        #sleep 10800 
        #main
fi
}


inc_backup () {
if [ ! -z $mysql_data_dir ]; then
	echo "inc_backup - $mysql_data_dir/bin-log.index found!"
	echo "inc_backup - beginning incremental backup of bin-log files"
	echo "inc_bcakup - s3://$s3_bucket$s3_bucket_folder/$year/$month/$day/$hostname/incremental_backup-$time.tar.gz"
	tar -czvf $backup_dir/incremental_backup-$time.tar.gz $mysql_data_dir/bin*
	s3cmd put --disable-multipart $backup_dir/incremental_backup-$time.tar.gz s3://$s3_bucket$s3_bucket_folder/$year/$month/$day/$hostname/inc/
        sleep 60
        main
else
	echo "inc_backup - $mysql_data_dir/bin-log.index not found!"
        echo "sleeping 60 seconds and restarting script."
        sleep 60
        main
#	exit 1
fi

}


# for sync backups to the container must be able to read the bin-log files via a volume mount.
# the default volume mount would be /var/lib/mysql:/binlog
# in the above volume mount you would set to - mysql_data_dir: /binlog 

sync_backup () {
if [ ! -z $mysql_data_dir ]; then
        echo "sync_backup - $mysql_data_dir/bin-log.index found!"
        echo "sync_backup - beginning sync backup of bin-log files"
	echo "sync_backup - s3://$s3_bucket$s3_bucket_folder/$year/$month/$day/$hostname/sync/"
	s3cmd sync --disable-multipart $mysql_data_dir/bin* s3://$s3_bucket$s3_folder/$year/$month/$day/$hostname/sync/
	echo "sync_backup - s3cmd sync --disable-multipart $mysql_data_dir/bin* s3://$s3_bucket$s3_folder/$year/$month/$day/$hostname/sync/"
        echo "sync_backup - s3cmd sync exited with code $?"
	echo "sync_backup - Sync Backup Complete"
	sync_backup_frequency
else
        echo "sync_backup - $mysql_data_dir/bin-log.index not found!"
        echo "sleep 15"
        sleep 15
        main
        #exit 1
fi

}

sync_backup_frequency () {
        echo "$sync_freq seconds until next backup."
        sleep $sync_freq
        main
}



sql_conn_test () {
mysql -h $db_host -u$db_user -p$db_password -e "show databases;"
if [ "$?"  == "0" ]; then
	echo "DB Connection Succeeded"
else
        echo "Unable to connect to $db_host, please verify your credentials and that the db server is running and accessible"
        echo "sleeping 60 seconds and restarting script."
        main
#	exit 1
fi
}

sql_db_test () {
mysql -h $db_host -u$db_user -p$db_password $db_name -e "show tables;"
if [ "$?"  == "0" ]; then
        echo "DB Connection Succeeded"
else
        echo "Unable to access $db_name, please verify your credentials and that the db server is running and accessible"
        echo "sleeping 60 seconds and restarting script."
        main
#        exit 1
fi
}

s3_config () {
isconfig=`cat /root/.s3cfg |grep "$s3_access_key"`
if [ "$isconfig" != "$s3_access_key" ]; then
	echo "updating /root/.s3cfg"
	sed -i s~s3accessKey~$s3_access_key~g /root/.s3cfg
	sed -i s~s3accessSecret~$s3_access_secret~g /root/.s3cfg
	sed -i s~s3Endpoint~$s3_endpoint~g /root/.s3cfg
	sed -i s~s3Bucket~$s3_bucket~g /root/.s3cfg
	sed -i s~s3bucketLocation~$s3_bucket_location~g /root/.s3cfg
	sed -i s~s3accessSecret~$s3_bucket_folder~g /root/.s3cfg
fi
}
get_backup_dir () {
if [ -z "$backup_folder" ]; then
        echo "backup_folder variable empty, setting backup_folder to /backup"
        backup_folder="/backup"
        backup_dir="/tmp/`echo $backup_folder |sed 's/\///g'`"
        echo "backup_dir = $backup_dir"

else
	backup_dir="/tmp/`echo $backup_folder |sed 's/\///g'`"
	echo "backup_dir = $backup_dir"
fi
}
cleanup () {

if [ -z $backup_dir ]; then
	echo "\$backup_dir not defined"
        echo "sleeping for 60 seconds and restarting script."
        sleep 60
        main
#	exit 1
else
        echo "Deleting $backup_dir"
	rm -r $backup_dir
fi
}

timestamp () {
time=`date +%Y-%m-%d_%H-%M-%S`
year=`date +%Y`
month=`date +%m`
day=`date +%d`
}

create_backup_dir () {
if [ ! -d $backup_dir ]; then
	mkdir $backup_dir
	echo "creating $backup_dir"
else
	echo "$backup_dir exists"
	#ls $backup_dir
fi
}


initial_config () {

if [ ! -f /root/.init_config ]; then
	touch /root/.init_config
	s3_config
fi
}

full_backup_freq () {
        echo "$full_freq seconds until next backup."
        sleep $full_freq
	main
}

######### Main ############
main () {
timestamp
echo "running docker_env"
docker_env

echo "running initial_config"
initial_config

echo "running get_backup_dir"
get_backup_dir

echo "running cleanup"
cleanup

echo "running create_backup_dir"
create_backup_dir

echo "running backup_opt"
backup_opt

#echo "running validation"
#validate_full_backup
}

#timestamp
main
