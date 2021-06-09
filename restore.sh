#!/bin/bash
set -e

namespace="" #Kubernetes namespace where CB CI is deployed.
instanceStatefulsetName="" #The statefulset name of the OC or master deployment.
s3FilePath="" #Path of the tar.gz file within the S3 bucket.
backupSource="" #source of backups. local or s3
s3BucketName="" #S3 bucketname containing backups.
backupFilePath="" #Path to the tar.gz backup file on the local directory
rescueContainerImage="governmentpaas/awscli" #Container with version if required, to use for the rescue pod.
cloudLocalDownloadDir="/tmp"

help(){
  echo -e "restore.sh Help\nUsage: restore.sh [parameters]\nParameters:\n--namespace <Kubernetes namespace>\n--instanceStatefulsetName <Operations Center or Controller statefulset name>\n--backupSource <local or s3>\n--backupFilePath <location of local backup file, tar.gz>\n--s3BucketName <S3 bucket name>\n--s3FilePath <Path to file in S3 bucket, tar.gz>\nOptional:\n--cloudLocalDownloadDir <Local Dir to download backup files, Default:/tmp>\n--rescueContainerImage <container image, Default:governmentpaas/awscli>"
}

while [ -n "$1" ]; do
  case "$1" in
    --namespace)
      namespace="$2"
      shift
      ;;
    --instanceStatefulsetName)
		  instanceStatefulsetName="$2"
		  shift
		  ;;
    --s3FilePath)
      s3FilePath="$2"
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
    --backupFilePath)
      backupFilePath="$2"
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

if [ -z $namespace ] || [ -z $instanceStatefulsetName ] || [ -z $backupSource ] || [ -z $rescueContainerImage ]
then
  echo "Execution parameters missing. Ignoring parameter inputs. Loading variables from config file."
  BASE_DIR=`echo $(dirname $0)`
  source $BASE_DIR/config
fi

if [ $backupSource = "s3" ]
then
  if [ -z $s3FilePath ] || [ -z $s3BucketName ]
  then
    echo "--s3FilePath and --s3BucketName parameters must be configured when using S3 backup source."
    help
    exit 1
  fi
elif [ $backupSource = "local" ]
then
  if [ -z $backupFilePath ]
  then
    echo "--backupFilePath parameter must be configured when using the local backup source."
    help
    exit 1
  fi
fi

echo "Scale down stateful set pods to 0 replicas"
kubectl --namespace=$namespace scale statefulset/$instanceStatefulsetName --replicas=0

#Launch rescue pod attaching the pvc
persistentVolumeClaim=$(kubectl -n $namespace get statefulset $instanceStatefulsetName -o jsonpath="{.spec.volumeClaimTemplates[0].metadata.name}")-${instanceStatefulsetName}-0
rescueStorageMountPath="/tmp/jenkins-home"
rescuePodName=rescue-pod-$instanceStatefulsetName
echo "Launching $rescuePodName with pvc $persistentVolumeClaim attached"

cat <<EOF | kubectl --namespace=$namespace create -f -

kind: Pod
apiVersion: v1
metadata:
  name: $rescuePodName
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  volumes:
    - name: rescue-storage
      persistentVolumeClaim:
        claimName: $persistentVolumeClaim
  containers:
    - name: rescue-container
      image: $rescueContainerImage
      resources:
        requests:
          ephemeral-storage: 4Gi
          cpu: 2000m
          memory: 2Gi
        limits:
          ephemeral-storage: 4Gi
          cpu: 2000m
          memory: 2Gi
      command: ['sh', '-c', 'echo The app is running! && sleep 100000' ]
      volumeMounts:
        - mountPath: $rescueStorageMountPath
          name: rescue-storage
EOF

localBackupFilePath="$cloudLocalDownloadDir/backup.tar.gz" #Default
case "$backupSource" in
  s3)
  echo "Downloading the backup file from S3 into local $localBackupFilePath directory"
  localBackupFilePath="$cloudLocalDownloadDir/$s3FilePath"
  aws s3 cp s3://${s3BucketName}/${s3FilePath} $localBackupFilePath
  ;;
  local)
  [ -f $backupFilePath ] && echo "Backup file $backupFilePath exists locally." || (echo "Backup file $backupFilePath is missing. Please ensure the file can be found on local or mounted directories." && exit 1)
  localBackupFilePath=$backupFilePath
  ;;
esac

echo "Waiting for the $rescuePodName to enter Ready state"
kubectl wait --namespace=$namespace --for=condition=Ready --timeout=600s pod/$rescuePodName

echo "Moving the backup file into the $rescuePodName"
kubectl cp --namespace=$namespace $localBackupFilePath $rescuePodName:/tmp/backup.tar.gz

# OPTIONAL - you can empty the directories, however the uncompress will overwrite any existing files
#echo "Empty $rescueStorageMountPath of all files and folders on pvc $persistentVolumeClaim"
#kubectl exec --namespace=$namespace $rescuePodName -- find $rescueStorageMountPath -type f -name "*.*" -delete || echo "Files deleted in jenkins-home"
#kubectl exec --namespace=$namespace $rescuePodName -- find $rescueStorageMountPath -type f -name "*" -delete || echo "Files deleted in jenkins-home"
#kubectl exec --namespace=$namespace $rescuePodName -- find $rescueStorageMountPath -mindepth 1 -type d -name "*" -exec rm -rf {} \; || echo "Folders deleted in jenkins-home"

echo "Uncompress the backup file into $rescueStorageMountPath"
kubectl exec --namespace=$namespace $rescuePodName -- tar -xvzf /tmp/backup.tar.gz --directory $rescueStorageMountPath

# OPTIONAL - enable if permissions are not set correctly, securityContext in the rescuepod should set permissions appropriately
#echo "Update ownership permissions recursively"
#kubectl exec --namespace=$namespace $rescuePodName -- chown -R 1000:1000 $rescueStorageMountPath

echo "Deleting the $rescuePodName"
kubectl --namespace=$namespace delete pod $rescuePodName

echo "Scale up $instanceStatefulsetName pods to 1 replica"
kubectl --namespace=$namespace scale statefulset/$instanceStatefulsetName --replicas=1
