#!/bin/sh

DATE=`date +%Y%m%d.%H`
DIR=$PWD/backup

DIR=$DIR/$DATE

# Backup object per project for easy restore
mkdir -p $DIR/projects
cd $DIR/projects
for i in `oc get projects --no-headers |grep Active |awk '{print $1}'`
do
  mkdir $i
  cd $i
  oc export namespace $i >ns.yml
  oc export project   $i >project.yml
  #for j in pods replicationcontrollers deploymentconfigs buildconfigs services routes pvc quota hpa secrets configmaps daemonsets deployments endpoints imagestreams ingress scheduledjobs jobs limitranges policies policybindings roles rolebindings resourcequotas replicasets serviceaccounts templates oauthclients petsets
  for j in deployments statefulsets deploymentconfigs buildconfigs services routes pvc secrets configmaps endpoints imagestreams policies policybindings roles rolebindings serviceaccounts 
  do
    mkdir $j
    cd $j
    for k in `oc get $j -n $i --no-headers |awk '{print $1}'`
    do
      echo export $j $k '-n' $i
      oc export $j $k -n $i >$k.yml
    done
    cd ..
  done
  cd ..
done


### Databases ###
for PROJECT in `oc get projects --no-headers |grep Active |awk '{print $1}'`
do
  oc get pods -n $PROJECT --output=go-template='{{range .items}}{{if .metadata.labels.backup}}{{.metadata.name}} {{or .metadata.labels.deploymentconfig (or .metadata.labels.app "-")}} {{ or .metadata.labels.backup "-"}} {{ or .metadata.labels.backupvolumemount "-" }}{{"\n"}}{{end}}{{end}}' \
   |while read POD DC BACKUP BACKUPVOLUMEMOUNT
  do
    [ "$BACKUP" == "-" ] && continue
    [ "$DC" == "-" ] && echo "ERROR: No app or deploymentconfig label for pod $POD" && continue
    echo "$POD in $PROJECT has the following \"backup\" label: $BACKUP"
    mkdir -p $DIR/../$BACKUP/$PROJECT/$DC  2>/dev/null
    DBNAME=""
    case $BACKUP in
      mysql)
        DBNAME=$(oc -n $PROJECT exec $POD -- /usr/bin/sh -c 'echo $MYSQL_DATABASE')
        echo "Backup database $DBNAME..."
        oc -n $PROJECT exec $POD -- /bin/bash -c 'mysqldump -h 127.0.0.1 -u $MYSQL_USER --password=$MYSQL_PASSWORD $MYSQL_DATABASE' >$DIR/../mysql/$PROJECT/$DC/$DBNAME.sql
        ;;
      postgresql)
        DBNAME=$(oc -n $PROJECT exec $POD -- /usr/bin/sh -c 'echo $POSTGRESQL_DATABASE')
        echo "Backup database $DBNAME..."
        oc -n $PROJECT exec $POD -- /bin/bash -c 'pg_dump -Fc $POSTGRESQL_DATABASE ' >$DIR/../postgresql/$PROJECT/$DC/$DBNAME.pg_dump_custom
        ;;
      mongodb)
        DBNAME=$(oc -n $PROJECT exec $POD -- /usr/bin/sh -c 'echo $MONGODB_DATABASE')
        echo "Backup database $DBNAME..."
        oc -n $PROJECT exec $POD -- /bin/bash -c 'mongodump -u $MONGODB_USER -p $MONGODB_PASSWORD -d $MONGODB_DATABASE --gzip --archive' >$DIR/../mongodb/$PROJECT/$DC/$DBNAME.mongodump.gz
        ;;
      fs)
        test -z "$BACKUPVOLUMEMOUNT" && echo "ERROR: Label 'backupvolumemount' not defined!" && continue
        FS=$(oc -n $PROJECT volume pod/$POD --name "$BACKUPVOLUMEMOUNT"|grep "mounted at"|awk '{print $NF}')
        if oc -n $PROJECT exec $POD -- test -d $FS
        then
          mkdir -p $DIR/../fs/$PROJECT/$DC/$FS/
          oc -n $PROJECT rsync --delete=true --quiet $POD:$FS/ $DIR/../fs/$PROJECT/$DC/$FS/
        else
          echo "ERROR: FS $FS is no valid directory in POD $POD!"
        fi
        ;;
      *)
        echo "ERROR: Unknown backup-method $BACKUP"
        ;;
    esac
  done
done


