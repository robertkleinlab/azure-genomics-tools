# postmsgen

Scripts for post-processing MSGEN GVCF calling.

This is for use with Azure Batch.  The -start script starts the node and downloads data.  The main postmsgen.sh script calls the tools to generate the statistics.
The specified tools need to be uploaded to the appropriate place in Azure storage for access.

