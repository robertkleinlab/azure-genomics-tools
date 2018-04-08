#!/bin/bash

export FDISK_SCRIPT=$AZ_BATCH_NODE_SHARED_DIR/script
# Make script file for fdisk
echo n > $FDISK_SCRIPT
echo p >> $FDISK_SCRIPT
echo >> $FDISK_SCRIPT
echo >> $FDISK_SCRIPT
echo >> $FDISK_SCRIPT
echo w >> $FDISK_SCRIPT
echo >> $FDISK_SCRIPT

#Fdisk and prepare /mnt2
cat $FDISK_SCRIPT | sudo fdisk /dev/sdc
sudo mke2fs /dev/sdc1
sudo mkdir /mnt2
sudo mount /dev/sdc1 /mnt2
sudo mkdir /mnt2/tmp
sudo chmod 777 /mnt2/tmp

if [ $(du -h /dev/sdc1 2>/dev/null | wc -l) -eq 0 ]; then
    exit 1;
fi

#install msgen
sudo apt-get update
sudo apt-get install -y build-essential libssl-dev libffi-dev libpython-dev python-dev python-pip

sudo -H pip install --upgrade pip
sudo -H pip install --upgrade --no-deps msgen
sudo -H pip install msgen

#Install curl, java, and R
sudo apt-get install -y curl openjdk-9-jre-headless r-base-core parallel

#Install Azure cmdline tools
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893
sudo apt-get install apt-transport-https
sudo apt-get update && sudo apt-get install azure-cli

# Update and upgrade
sudo apt-get update
sudo apt-get upgrade -y

export AZURE_STORAGE_CONNECTION_STRING= # ***PUT YOUR CONNECTION STRING HERE***

#Set bins
export MAIN_JOB_DIR=$AZ_BATCH_NODE_SHARED_DIR

echo $AZURE_STORAGE_CONNECTION_STRING > $MAIN_JOB_DIR/localconnection.txt

mkdir $MAIN_JOB_DIR/bin

export SAMTOOLS=$MAIN_JOB_DIR/bin/samtools
az storage blob download -c batchresources -n bin/samtools -f $SAMTOOLS

export PICARD=$MAIN_JOB_DIR/bin/picard.jar
az storage blob download -c batchresources -n bin/picard.jar -f $PICARD

export VERIFYBAMID=$MAIN_JOB_DIR/bin/verifyBamID
az storage blob download -c batchresources -n bin/verifyBamID -f $VERIFYBAMID

export BGZIP=$MAIN_JOB_DIR/bin/bgzip
az storage blob download -c batchresources -n bin/bgzip -f $BGZIP

export TABIX=$MAIN_JOB_DIR/bin/tabix
az storage blob download -c batchresources -n bin/tabix -f $TABIX

chmod a+rx $MAIN_JOB_DIR/bin/*


# Set where download goes
export BAMPREFIX=/mnt2/tmp/${1}_${2}_${3}_${4}

#Set output dirs
export BAMOUTPREFIX=$AZ_BATCH_TASK_WORKING_DIR/outputs/$4
mkdir $AZ_BATCH_TASK_WORKING_DIR/outputs

#Set data dirs
mkdir $MAIN_JOB_DIR/data
export VERIFYBAMIDVCF=$MAIN_JOB_DIR/data/verifyBamId.SNPs.omni2.5.b37.vcf
az storage blob download -c batchresources -n data/verifyBamId.SNPs.omni2.5.b37.vcf -f $VERIFYBAMIDVCF

export REFERENCE=$MAIN_JOB_DIR/data/human_g1k_v37
az storage blob download -c batchresources -n data/human_g1k_v37.fasta.gz -f $REFERENCE.fasta.gz
gunzip $REFERENCE.fasta.gz
az storage blob download -c batchresources -n data/human_g1k_v37.dict -f $REFERENCE.dict

az storage blob download -c batchresources -n data/dbsnp_138.b37.vcf.gz -f $MAIN_JOB_DIR/data/dbsnp_138.b37.vcf.gz
az storage blob download -c batchresources -n data/dbsnp_138.b37.vcf.gz.tbi -f $MAIN_JOB_DIR/data/dbsnp_138.b37.vcf.gz.tbi


az storage blob download -c batchresources -n postmsgen.sh -f $MAIN_JOB_DIR/postmsgen.sh
if [ ! -d /usr/local/bin ]; then
    sudo mkdir /usr/local/bin
    sudo chmod 755 /usr/local/bin
fi
sudo mv $MAIN_JOB_DIR/postmsgen.sh /usr/local/bin/postmsgen.sh
chmod 755 /usr/local/bin/postmsgen.sh

chmod -R a+rX $MAIN_JOB_DIR

exit 0;
