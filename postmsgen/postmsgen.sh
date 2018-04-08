#!/bin/bash

## WGS Calling script for Azure -- bam stats and fastq compress
## Copyright Icahn School of Medicine at Mount Sinai 2017-2018
## Based on WDL script from the Broad Institute: https://raw.githubusercontent.com/openwdl/wdl/develop/scripts/broad_pipelines/germline-short-variant-discovery/gvcf-generation-per-sample/1.0.0/GOTC_PairedEndSingleSampleWf.wdl
##

## Copyright Broad Institute, 2017
##
## This WDL pipeline implements data pre-processing and initial variant calling (GVCF
## generation) according to the GATK Best Practices (June 2016) for germline SNP and
## Indel discovery in human whole-genome sequencing (WGS) data.
##
## Requirements/expectations :
## - Human whole-genome pair-end sequencing data in unmapped BAM (uBAM) format
## - One or more read groups, one per uBAM file, all belonging to a single sample (SM)
## - Input uBAM files must additionally comply with the following requirements:
## - - filenames all have the same suffix (we use ".unmapped.bam")
## - - files must pass validation by ValidateSamFile
## - - reads are provided in query-sorted order
## - - all reads must have an RG tag
## - GVCF output names must end in ".g.vcf.gz"
## - Reference genome must be Hg38 with ALT contigs
##
## Runtime parameters are optimized for Broad's Google Cloud Platform implementation.
## For program versions, see docker containers.
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3) (see LICENSE in
## https://github.com/broadinstitute/wdl). Note however that the programs it calls may
## be subject to different licenses. Users are responsible for checking that they are
## authorized to run all programs before running this script. Please see the docker
## page at https://hub.docker.com/r/broadinstitute/genomes-in-the-cloud/ for detailed
## licensing information pertaining to the included programs.


#USAGE: postmsgen.sh <container> <bamprefix>

export CONTAINER=$1

export AZURE_STORAGE_CONNECTION_STRING=$(cat $AZ_BATCH_NODE_SHARED_DIR/localconnection.txt)

#Set bins
export MAIN_JOB_DIR=$AZ_BATCH_NODE_SHARED_DIR

export SAMTOOLS=$MAIN_JOB_DIR/bin/samtools
export PICARD=$MAIN_JOB_DIR/bin/picard.jar
export VERIFYBAMID=$MAIN_JOB_DIR/bin/verifyBamID
export BGZIP=$MAIN_JOB_DIR/bin/bgzip
export TABIX=$MAIN_JOB_DIR/bin/tabix

# Set where download goes
export BAMPREFIX=/mnt2/tmp/${CONTAINER}.$2

#Set output dirs
export BAMOUTPREFIX=$AZ_BATCH_TASK_WORKING_DIR/outputs/$CONTAINER.$2
mkdir $AZ_BATCH_TASK_WORKING_DIR/outputs

#Set data dirs
export VERIFYBAMIDVCF=$MAIN_JOB_DIR/data/verifyBamId.SNPs.omni2.5.b37.vcf
export REFERENCE=$MAIN_JOB_DIR/data/human_g1k_v37
export DBSNP=$MAIN_JOB_DIR/data/dbsnp_138.b37.vcf.gz

# First do the VCFs
echo Doing VCFs

az storage blob download -c $CONTAINER -n $CONTAINER.$2.g.vcf -f $BAMPREFIX.g.vcf
cat $BAMPREFIX.g.vcf | VCFNAME=$2 perl -e 'while (<>) { if (/^#CH/) { chop(); @s = split (/\t/); $s[$#s] = $ENV{"VCFNAME"}; print join("\t", @s) . "\n"; } else { print $_; }}' | $BGZIP -c > $AZ_BATCH_TASK_WORKING_DIR/$CONTAINER.$2.gvcf.gz
$TABIX -p vcf $AZ_BATCH_TASK_WORKING_DIR/$CONTAINER.$2.gvcf.gz

echo Done with VCF gzipping
rm $BAMPREFIX.g.vcf
echo "java -Xms2000m -jar $PICARD CollectVariantCallingMetrics INPUT=$AZ_BATCH_TASK_WORKING_DIR/$CONTAINER.$2.gvcf.gz OUTPUT=$BAMOUTPREFIX.vcf.metrics SEQUENCE_DICTIONARY=$REFERENCE.dict GVCF_INPUT=true DBSNP=$DBSNP > $BAMOUTPREFIX.CollectVariantCallingMetrics.run 2>&1" > $AZ_BATCH_TASK_WORKING_DIR/cmds

# Now the bams
echo Doing BAMs

az storage blob download -c $CONTAINER -n $CONTAINER.$2.bam -f ${BAMPREFIX}.bam
az storage blob download -c $CONTAINER -n $CONTAINER.$2.bam.bai -f ${BAMPREFIX}.bam.bai

echo "java -Xms5000m -jar $PICARD \
      CollectMultipleMetrics \
      INPUT=${BAMPREFIX}.bam \
      OUTPUT=${BAMOUTPREFIX}.read-metrics \
      ASSUME_SORTED=true \
      PROGRAM='CollectBaseDistributionByCycle' \
      PROGRAM='CollectInsertSizeMetrics' \
      PROGRAM='MeanQualityByCycle' \
      PROGRAM='QualityScoreDistribution' \
      METRIC_ACCUMULATION_LEVEL='ALL_READS' > $BAMOUTPREFIX.CollectMultipleMetrics.read-metrics.run 2>&1" >> $AZ_BATCH_TASK_WORKING_DIR/cmds


# Check contamination with verifyBamId.  Note I use UMich verifyBamID, while Broad uses their own
echo "$VERIFYBAMID \
    --bam $BAMPREFIX.bam --vcf $VERIFYBAMIDVCF \
    --out $BAMOUTPREFIX.verifyBamID \
    --chip-none --maxDepth 1000 --precise --ignoreRG --noPhoneHome > $BAMOUTPREFIX.verifybamid.run 2>&1" >> $AZ_BATCH_TASK_WORKING_DIR/cmds


echo "$SAMTOOLS stats $BAMPREFIX.bam > $BAMOUTPREFIX.bamstats 2> $BAMOUTPREFIX.samtools-stats.run" >> $AZ_BATCH_TASK_WORKING_DIR/cmds

echo "java -Xms5000m -jar $PICARD \
      CollectMultipleMetrics \
      INPUT=${BAMPREFIX}.bam \
      REFERENCE_SEQUENCE=$REFERENCE.fasta \
      OUTPUT=${BAMOUTPREFIX}.rg-metrics \
      ASSUME_SORTED=true \
      PROGRAM='CollectAlignmentSummaryMetrics' \
      PROGRAM='CollectGcBiasMetrics' \
      METRIC_ACCUMULATION_LEVEL='READ_GROUP' > $BAMOUTPREFIX.CollectMultipleMetrics.rg-metrics.run 2>&1" >> $AZ_BATCH_TASK_WORKING_DIR/cmds

echo "java -Xms5000m -jar $PICARD \
      CollectMultipleMetrics \
      INPUT=$BAMPREFIX.bam \
      REFERENCE_SEQUENCE=$REFERENCE.fasta \
      OUTPUT=$BAMOUTPREFIX.metrics \
      ASSUME_SORTED=true \
      PROGRAM='CollectAlignmentSummaryMetrics' \
      PROGRAM='CollectInsertSizeMetrics' \
      PROGRAM='CollectSequencingArtifactMetrics' \
      PROGRAM='CollectGcBiasMetrics' \
      PROGRAM='QualityScoreDistribution' \
      METRIC_ACCUMULATION_LEVEL='SAMPLE' \
      METRIC_ACCUMULATION_LEVEL='LIBRARY' > $BAMOUTPREFIX.CollectMultipleMetrics.metrics.run 2>&1" >> $AZ_BATCH_TASK_WORKING_DIR/cmds


echo "java -Xms2000m -jar $PICARD \
      CollectWgsMetrics \
      INPUT=$BAMPREFIX.bam \
      VALIDATION_STRINGENCY=SILENT \
      REFERENCE_SEQUENCE=$REFERENCE.fasta \
      INCLUDE_BQ_HISTOGRAM=true \
      OUTPUT=$BAMOUTPREFIX.wgs-metrics > $BAMOUTPREFIX.CollectWgsMetrics.run 2>&1" >> $AZ_BATCH_TASK_WORKING_DIR/cmds

echo "java -Xms2000m -jar $PICARD \
    CollectRawWgsMetrics \
    INPUT=$BAMPREFIX.bam \
    VALIDATION_STRINGENCY=SILENT \
    REFERENCE_SEQUENCE=$REFERENCE.fasta \
    INCLUDE_BQ_HISTOGRAM=true \
    OUTPUT=$BAMOUTPREFIX.raw-wgs-metrics > $BAMOUTPREFIX.CollectRawWgsMetrics.run 2>&1" >> $AZ_BATCH_TASK_WORKING_DIR/cmds


echo "java -Xms5000m -jar $PICARD \
      ValidateSamFile \
      INPUT=$BAMPREFIX.bam \
      OUTPUT=$BAMOUTPREFIX.validation_report \
      REFERENCE_SEQUENCE=$REFERENCE.fasta \
      MAX_OUTPUT=10000000 \
      IGNORE=null \
      MODE=VERBOSE \
      IS_BISULFITE_SEQUENCED=false > $BAMOUTPREFIX.ValidateSam.run 2>&1" >> $AZ_BATCH_TASK_WORKING_DIR/cmds

cat $AZ_BATCH_TASK_WORKING_DIR/cmds | parallel

export AZURE_STORAGE_CONNECTION_STRING= # *** PUT CONNECTION STRING HERE ***

az storage directory create -s sequencingmetrics -n westus2/$CONTAINER

for file in ${BAMOUTPREFIX}*; do
    filename=$(basename $file)
    az storage file upload -s sequencingmetrics --source $file -p westus2/$CONTAINER/$filename
done

az storage blob upload -c gvcfs -n westus2/$CONTAINER/$CONTAINER.$2.gvcf.gz -f $AZ_BATCH_TASK_WORKING_DIR/$CONTAINER.$2.gvcf.gz
az storage blob upload -c gvcfs -n westus2/$CONTAINER/$CONTAINER.$2.gvcf.gz.tbi -f $AZ_BATCH_TASK_WORKING_DIR/$CONTAINER.$2.gvcf.gz.tbi

rm -f ${BAMPREFIX}*
rm $AZ_BATCH_TASK_WORKING_DIR/$CONTAINER.$2.gvcf.gz*

if [ `az storage blob exists -c gvcfs -n westus2/$CONTAINER/$CONTAINER.$2.gvcf.gz -o tsv` == 'True' ]; then echo gvcf.gz exists; else exit 1; fi
if [ `az storage blob exists -c gvcfs -n westus2/$CONTAINER/$CONTAINER.$2.gvcf.gz.tbi -o tsv` == 'True' ]; then echo gvcf.gz.tbi exists; else exit 1; fi
if [ `az storage file list -s sequencingmetrics -o table --path westus2/$CONTAINER/ | grep $2 | wc -l` -eq 56 ]; then echo All seqmetrics there; else exit 1; fi

exit 0;

    

