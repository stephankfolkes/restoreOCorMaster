#!/bin/bash

namespace="cloudbees-core"
rescueContainerImage="governmentpaas/awscli"
backupSource="local"
s3BucketName=cb-ci-backups
cloudLocalDownloadDir=/tmp
controllerList=controllerList.csv

#Create log directory if not exists
mkdir -p $cloudLocalDownloadDir/logs

while read -r controllerAssociation
do
  controllerStatefulset="$(echo $controllerAssociation | cut -d "," -f 1)"
  filePath="$(echo $controllerAssociation | cut -d "," -f 2)"
  echo "Restoring $controllerStatefulset from $backupSource backup".
  echo "Read log for $controllerStatefulset at: $cloudLocalDownloadDir/logs/$controllerStatefulset-restore.log"

  if [[ $backupSource = "local" ]]; then
    bash restore.sh --namespace $namespace --instanceStatefulsetName $controllerStatefulset --backupFilePath "$filePath" --backupSource $backupSource --rescueContainerImage $rescueContainerImage > "$cloudLocalDownloadDir/logs/$controllerStatefulset-restore.log" 2>&1 &
  elif [[ $backupSource = "s3" ]]; then
    bash restore.sh --namespace $namespace --instanceStatefulsetName $controllerStatefulset --s3FilePath "$filePath" --s3BucketName $s3BucketName --backupSource $backupSource --cloudLocalDownloadDir $cloudLocalDownloadDir --rescueContainerImage $rescueContainerImage > "$cloudLocalDownloadDir/logs/$controllerStatefulset-restore.log" 2>&1 &
  fi
done < $controllerList

echo "Read logs and progress in $cloudLocalDownloadDir/logs"
