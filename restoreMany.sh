#!/bin/bash

namespace=""
rescueContainerImage=""
backupSource=""
s3BucketName=""
cloudLocalDownloadDir=""
controllerList=""
BASE_DIR=""

help(){
  echo -e "restoreMany.sh Help\nUsage: restoreMany.sh [parameters]\nParameters:\n--namespace <Kubernetes namespace>\n--backupSource <local or s3>\nOptional:\n--s3BucketName <S3 bucket name>\n--cloudLocalDownloadDir <Local Dir to download backup files, Default:/tmp>\n--rescueContainerImage <container image, Default:governmentpaas/awscli>\n--controllerList <CSV file, Default:controllerList.csv>"
}

while [ -n "$1" ]; do
  case "$1" in
    --namespace)
      namespace="$2"
      shift
      ;;
    --backupSource)
      backupSource="$2"
      shift
      ;;
    --s3BucketName)
      s3BucketName="$2"
      shift
      ;;
    --controllerList)
      controllerList="$2"
      shift
      ;;
    --rescueContainerImage)
      rescueContainerImage="$2"
      shift
      ;;
    --cloudLocalDownloadDir)
      cloudLocalDownloadDir="$2"
      shift
      ;;
    *) echo "Option $1 not recognized" && help && exit 1 ;;
	esac
	shift
done

if [ -z $BASE_DIR ]
then
  BASE_DIR=`echo $(dirname $0)`
fi

if [ -z $namespace ] || [ -z $backupSource ]
then
  echo "Mandatory Execution parameters missing. Ignoring parameter inputs. Loading variables from config file."
  source $BASE_DIR/config

  if [ -z $namespace ]
  then
    echo "namespace not set. Stopping exection."
    exit 1
  fi
fi

if [ -z $backupSource ]
then
  echo "backupSource not set. Stopping exection."
  exit 1
elif [ $backupSource == 's3' ]
then
  if [ -z $s3BucketName ]
  then
    echo "s3BucketName not set. Stopping exection."
    exit 1
  fi
fi

if [ -z $controllerList ]
then
  echo "controllerList not set. Using default value $BASE_DIR/controllerList.csv"
  controllerList=$BASE_DIR/controllerList.csv
fi

if [ -z $rescueContainerImage ]
then
  echo "rescueContainerImage not set. Using default value governmentpaas/awscli"
  rescueContainerImage="governmentpaas/awscli"
fi

if [ -z $cloudLocalDownloadDir ]
then
  echo "cloudLocalDownloadDir not set. Using default value /tmp"
  cloudLocalDownloadDir=/tmp
fi

#Create log directory if not exists
mkdir -p $cloudLocalDownloadDir/logs

while read -r controllerAssociation
do
  controllerStatefulset="$(echo $controllerAssociation | cut -d "," -f 1)"
  filePath="$(echo $controllerAssociation | cut -d "," -f 2)"
  echo "Restoring $controllerStatefulset from $backupSource backup".
  echo "Read log for $controllerStatefulset at: $cloudLocalDownloadDir/logs/$controllerStatefulset-restore.log"

  if [[ $backupSource = "local" ]]; then
    bash restore.sh --namespace $namespace --instanceStatefulsetName $controllerStatefulset --backupFilePath "$filePath" --backupSource $backupSource --rescueContainerImage $rescueContainerImage > "$cloudLocalDownloadDir/logs/$controllerStatefulset-restore.log" 2>&1
  elif [[ $backupSource = "s3" ]]; then
    bash restore.sh --namespace $namespace --instanceStatefulsetName $controllerStatefulset --s3FilePath "$filePath" --s3BucketName $s3BucketName --backupSource $backupSource --cloudLocalDownloadDir $cloudLocalDownloadDir --rescueContainerImage $rescueContainerImage > "$cloudLocalDownloadDir/logs/$controllerStatefulset-restore.log" 2>&1
  fi
done < $controllerList

echo "Restore Many script complete."
