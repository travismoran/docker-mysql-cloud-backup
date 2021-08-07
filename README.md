### Update 2021080602
```
Added sync functionality and ENV vars.
Added .dev.env file example for populating compose secrets.
To launch docker-compose.yml file myapp.mysql-backup.yml
step 1 - cp .dev.env .prod.env
step 2 - update key/secret/bucket to real values
step 3 - run compose up command:
docker-compose --env-file .prod.env -f myapp-mysql-backup.yml up -d
```


### Update 2021080601
```
Added New ENV variables for backup frequency.
full_freq: 3600 # full backup every 3600 seconds
sync_freq: 30   # syncronize bin.log files to cloud every 30 seconds
```
```
# for sync backups to the container must be able to read the bin-log files via a volume mount.
# the default volume mount would be /var/lib/mysql:/binlog
# in the above volume mount you would set to - mysql_data_dir: /binlog
```

### Below examples expect Rancher 1.6 as the environment and includes deprecated ofelia cron scheduler(replaced by sleep functions in entrypoint script)

### Update 20210804

Example sync of binlogs service:
```
  docker-mysql-backup-sync-myapp-replica:
    mem_limit: 536870912
    image: myapp/docker-mysql-backup:latest
    environment:
      backup_folder: /backups
      backup_type: sync
      db_host: myapp-replica
      db_name: mysql
      db_password: root
      db_user: root
      hostname: prod
      mysql_data_dir: /var/lib/mysql
      s3_access_key: ${S3KEY}
      s3_access_secret: ${S3SECRET}
      s3_bucket: ${S3BUCKET}
      s3_bucket_folder: /myapp_db
      s3_bucket_location: US
      s3_endpoint: nyc3.digitaloceanspaces.com
    stdin_open: true
    volumes:
    - /var/db:/var/lib/mysql
    tty: true
    cpuset: '0'
    cpu_shares: 512
    labels:
      io.rancher.scheduler.affinity:host_label: server=myapp-replica-db
      io.rancher.container.pull_image: always
      cron.schedule: '* 0 */13 * * *'
      cron.action: restart
```


Updating full backups to run every hour
```
  docker-mysql-backup-full-myapp-replica:
    image: myapp/docker-mysql-backup:latest
    environment:
      backup_folder: /backups
      backup_type: full
      db_host: myapp-replica
      db_name: mysql
      db_password: root
      db_user: root
      hostname: prod
      mysql_data_dir: /var/lib/mysql
      s3_access_key: ${S3KEY}
      s3_access_secret: ${S3SECRET}
      s3_bucket: ${S3BUCKET}
      s3_bucket_folder: /myapp_db
      s3_bucket_location: US
      s3_endpoint: nyc3.digitaloceanspaces.com
    stdin_open: true
    tty: true
    labels:
      io.rancher.scheduler.affinity:host_label: server=myapp-replica-db
      io.rancher.container.pull_image: always
      cron.schedule: '* 0 */13 * * *'
      cron.action: restart
```

##### Example docker-compose.yml #####
##### Cron schedule 0 */6 * * * * = every 6 hours ######
##### Cron requires rancher crontab service from catalog to function #####
```
  docker-mysql-backup-sync:
    image: myapp/docker-mysql-backup:latest
    environment:
      backup_folder: /backups
      db_host: mysql
      db_name: mysql
      db_password: asdfsdf
      db_user: root
      s3_access_key: ${S3KEY}
      s3_access_secret: ${S3SECRET}
      s3_bucket: ${S3BUCKET}
      s3_bucket_folder: /myapp_db
      s3_bucket_location: US
      s3_endpoint: nyc3.digitaloceanspaces.com
      backup_type: sync
      hostname: test_prod
    stdin_open: true
    volumes:
    - /data/myapp/var/docker/myapp/website/mysql54/data:/var/lib/mysql
    - mysql_backups:/backups
    tty: true
    labels:
      io.rancher.container.pull_image: always
      cron.schedule: ' * */10 * * * *'
      cron.action: restart
  docker-mysql-backup-full:
    image: myapp/docker-mysql-backup:latest
    environment:
      backup_folder: /backups
      db_host: mysql
      db_name: mysql
      db_password: asdfasdf
      db_user: root
      s3_access_key: ${S3KEY}
      s3_access_secret: ${S3SECRET}
      s3_bucket: ${S3BUCKET}
      s3_bucket_folder: /myapp_db
      s3_bucket_location: US
      s3_endpoint: nyc3.digitaloceanspaces.com
      backup_type: full
      hostname: test_prod
    stdin_open: true
    volumes:
    - mysql_backups:/backups
    - /data/myapp/var/docker/myapp/website/mysql54/data:/var/lib/mysql
    tty: true
    labels:
      io.rancher.container.pull_image: always
      cron.schedule: '* 0 */12 * * *'
      cron.action: restart
  docker-mysql-backup-inc:
    image: myapp/docker-mysql-backup:latest
    environment:
      backup_folder: /backups
      db_host: mysql
      db_name: mysql
      db_password: asdfasfd
      db_user: root
      s3_access_key: ${S3KEY}
      s3_access_secret: ${S3SECRET}
      s3_bucket: ${S3BUCKET}
      s3_bucket_folder: /myapp_db
      s3_bucket_location: US
      s3_endpoint: nyc3.digitaloceanspaces.com
      backup_type: inc
      hostname: test_prod
    stdin_open: true
    volumes:
    - /data/myapp/var/docker/myapp/website/mysql54/data:/var/lib/mysql
    - mysql_backups:/backups
    tty: true
    labels:
      io.rancher.container.pull_image: always
      cron.schedule: '* 0 * * * *'
      cron.action: restart


```
