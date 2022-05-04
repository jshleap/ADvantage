version 1.0

import "https://raw.githubusercontent.com/lilab-bcb/cumulus/aws-backend/workflows/cellranger/cellranger_workflow.wdl" as crw
import "cumulus2dsdb.wdl" as dsdb
import "immcantation.wdl" as imm

workflow cellranger_workflow {
    input {
        # 6 - 10 columns (Library, Reference, Flowcell, Lane, Index, Sample, [Chemistry, DataType, FeatureBarcodeFile, Link]).
        File input_csv_file
        # Output directory, gs URL
        String output_directory
        # If run mkfastq
        Boolean run_mkfastq = true
        # If run count
        Boolean run_count = true

        # for mkfastq
        # Whether to delete input_bcl_directory, default: false
        Boolean delete_input_bcl_directory = false
        # Number of allowed mismatches per index
        Int? mkfastq_barcode_mismatches
        # Only demultiplex samples identified by an i7-only sample index, ignoring dual-indexed samples.  Dual-indexed samples will not be demultiplexed.
        Boolean mkfastq_filter_single_index = false
        # Override the read lengths as specified in RunInfo.xml
        String? mkfastq_use_bases_mask
        # Delete undetermined FASTQ files generated by bcl2fastq2
        Boolean mkfastq_delete_undetermined = false


        # For cellranger count
        # Force pipeline to use this number of cells, bypassing the cell detection algorithm, mutually exclusive with expect_cells.
        Int? force_cells
        # Expected number of recovered cells. Mutually exclusive with force_cells
        Int? expect_cells
        # If count reads mapping to intronic regions
        Boolean include_introns = false
        # If generate bam outputs. This is also a spaceranger argument.
        Boolean no_bam = false
        # Perform secondary analysis of the gene-barcode matrix (dimensionality reduction, clustering and visualization). Default: false.
        Boolean secondary = false

        # For vdj
        # Do not align reads to reference V(D)J sequences before de novo assembly. Default: false
        Boolean vdj_denovo = false
        String immcantation_version = "4.3.0"
        String organism = 'human'


        # Force the analysis to be carried out for a particular chain type. The accepted values are:
        #   "auto" for auto detection based on TR vs IG representation (default),
        #   "TR" for T cell receptors,
        #   "IG" for B cell receptors,
        # Use this in rare cases when automatic chain detection fails.
        String vdj_chain = "auto"

        # For extracting ADT count

        # Barcode start position at Read 2 (0-based coordinate) for CRISPR
        Int? crispr_barcode_pos
        # scaffold sequence for Perturb-seq, default is "", which for Perturb-seq means barcode starts at position 0 of read 2
        String scaffold_sequence = ""
        # maximum hamming distance in feature barcodes
        Int max_mismatch = 3
        # minimum read count ratio (non-inclusive) to justify a feature given a cell barcode and feature combination, only used for data type crispr
        Float min_read_ratio = 0.1

        # For atac

        # For atac, choose the algorithm for dimensionality reduction prior to clustering and tsne: 'lsa' (default), 'plsa', or 'pca'.
        String? atac_dim_reduce = "lsa"
        # A BED file to override peak caller
        File? peaks

        # For arc

        # Disable counting of intronic reads.
        Boolean arc_gex_exclude_introns = false
        # Cell caller override: define the minimum number of ATAC transposition events in peaks (ATAC counts) for a cell barcode.
        Int? arc_min_atac_count
        # Cell caller override: define the minimum number of GEX UMI counts for a cell barcode.
        Int? arc_min_gex_count

        # For multi

        # CMO set CSV file, delaring CMO constructs and associated barcodes
        File? cmo_set

        String cellranger_version = "6.1.2"
        String cumulus_feature_barcoding_version = "0.7.0"
        String cellranger_atac_version = "2.0.0"
        String cellranger_arc_version = "2.0.1"
        String config_version = "0.2"


        # Which docker registry to use: quay.io/cumulus (default) or cumulusprod
        String docker_registry = "quay.io/cumulus"
        # Number of cpus per cellranger and spaceranger job
        Int num_cpu = 32
        # Memory string
        String memory = "120G"

        # Number of cpus for cellranger-atac count
        Int atac_num_cpu = 64
        # Memory string for cellranger-atac count
        String atac_memory = "57.6G"

        # Optional memory string for cumulus_adt
        String feature_memory = "32G"

        # Number of cpus for cellranger-arc count
        Int arc_num_cpu = 64
        # Memory string for cellranger-arc count
        String arc_memory = "160G"

        # Optional disk space for mkfastq.
        Int mkfastq_disk_space = 1500
        # Optional disk space needed for cell ranger count.
        Int count_disk_space = 500
        # Optional disk space needed for cell ranger vdj.
        Int vdj_disk_space = 500
        # Optional disk space needed for cumulus_adt
        Int feature_disk_space = 100
        # Optional disk space needed for cellranger-atac count
        Int atac_disk_space = 500
        # Optional disk space needed for cellranger-arc count
        Int arc_disk_space = 700

        # Cloud backend: aws or gcp
        String backend = "aws"
        # Number of preemptible tries
        Int preemptible = 2
        # Max number of retries for AWS instance
        Int awsMaxRetries = 5

        # If register data to DataSetDB
        Boolean write_to_dsdb = true
        String dsdb_project_id = ""
        String dsdb_project_authors = ""
        String dsdb_project_title = ""
        String dsdb_project_description = ""

    }

    # Index TSV file
    File acronym_file = if backend == "aws" then "s3://gred-cumulus-ref/resources/cellranger/index.tsv" else "gs://gred-cumulus-ref/resources/cellranger/index.tsv"
    # Genomitory index file
    String gmty_index_file = if backend == "aws" then "s3://gred-cumulus-ref/resources/gmty_index.tsv" else "gs://gred-cumulus-ref/resources/gmty_index.tsv"
    # Cumulus project's private registry.
    String cumulus_private_registry = if backend == "aws" then "752311211819.dkr.ecr.us-west-2.amazonaws.com" else "gcr.io/gred-cumulus-sb-01-991a49c4"
    # Google cloud zones, default to Roche Science Cloud zones
    String zones = "us-west1-a us-west1-b us-west1-c"
    String awsQueueArn = "arn:aws:batch:us-west-2:752311211819:job-queue/priority-gred-cumulus"

    call generate_cellranger_config {
       input:
           input_csv_file = input_csv_file,
           write_to_dsdb = write_to_dsdb,
           backend = backend,
           zones = zones,
           preemptible = preemptible,
           docker_registry = docker_registry,
           awsMaxRetries = awsMaxRetries,
           config_version = config_version
    }

    call crw.cellranger_workflow as cellranger_workflow {
        input:
            input_csv_file = generate_cellranger_config.cellranger_sample_sheet,
            output_directory = output_directory,
            run_mkfastq = run_mkfastq,
            run_count = run_count,
            delete_input_bcl_directory = delete_input_bcl_directory,
            mkfastq_barcode_mismatches = mkfastq_barcode_mismatches,
            mkfastq_filter_single_index = mkfastq_filter_single_index,
            mkfastq_use_bases_mask = mkfastq_use_bases_mask,
            mkfastq_delete_undetermined = mkfastq_delete_undetermined,
            force_cells = force_cells,
            expect_cells = expect_cells,
            include_introns = include_introns,
            no_bam = no_bam,
            secondary = secondary,
            vdj_denovo = vdj_denovo,
            vdj_chain = vdj_chain,
            crispr_barcode_pos = crispr_barcode_pos,
            scaffold_sequence = scaffold_sequence,
            max_mismatch = max_mismatch,
            min_read_ratio = min_read_ratio,
            atac_dim_reduce = atac_dim_reduce,
            peaks = peaks,
            arc_gex_exclude_introns = arc_gex_exclude_introns,
            arc_min_atac_count = arc_min_atac_count,
            arc_min_gex_count = arc_min_gex_count,
            cmo_set = cmo_set,
            acronym_file = acronym_file,
            cellranger_version = cellranger_version,
            cumulus_feature_barcoding_version = cumulus_feature_barcoding_version,
            cellranger_atac_version = cellranger_atac_version,
            cellranger_arc_version = cellranger_arc_version,
            config_version = config_version,
            docker_registry = docker_registry,
            mkfastq_docker_registry = cumulus_private_registry,
            zones = zones,
            backend = backend,
            num_cpu = num_cpu,
            memory = memory,
            atac_num_cpu = atac_num_cpu,
            atac_memory = atac_memory,
            feature_memory = feature_memory,
            arc_num_cpu = arc_num_cpu,
            arc_memory = arc_memory,
            mkfastq_disk_space = mkfastq_disk_space,
            count_disk_space = count_disk_space,
            vdj_disk_space = vdj_disk_space,
            feature_disk_space = feature_disk_space,
            atac_disk_space = atac_disk_space,
            arc_disk_space = arc_disk_space,
            preemptible = preemptible,
            awsMaxRetries = awsMaxRetries,
            awsQueueArn = awsQueueArn
    }
     if (defined(cellranger_workflow.count_outputs["vdj"])) {
        call imm.run_changeo_10x {
            input:
                vdj_folders = select_first([cellranger_workflow.count_outputs["vdj"]]),
                organism = organism,
                backend = backend,
                zones = zones,
                preemptible = preemptible,
                docker_registry = docker_registry,
                version = immcantation_version,
                awsMaxRetries = awsMaxRetries
        }
    }

    if (write_to_dsdb) {
        call dsdb.write_to_DataSetDB_multiome as write_to_dsdb_multiome {
            input:
                map_file = select_first([generate_cellranger_config.map_file]),
                count_outputs = cellranger_workflow.count_outputs,
                output_directory = output_directory,
                gmty_index_file = gmty_index_file,
                genome = select_first([generate_cellranger_config.genome]),
                project_id = dsdb_project_id,
                project_authors = dsdb_project_authors,
                project_title = dsdb_project_title,
                project_description = dsdb_project_description,
                docker_registry = cumulus_private_registry,
                backend = backend,
                num_cpu = 4,
                memory = "10G",
                zones = zones,
                disk_space = 100,
                preemptible = preemptible,
                awsMaxRetries = awsMaxRetries,
                awsQueueArn = awsQueueArn
        }
    }

    output {
        String? count_matrix = cellranger_workflow.count_matrix
        Array[Array[String]?] count_outputs = cellranger_workflow.count_outputs
        Array[Array[String]?] fastq_outputs = cellranger_workflow.fastq_outputs
        String? dsdb_id = write_to_dsdb_multiome.output_dsdb_id
    }
}

task generate_cellranger_config {
    input {
        File input_csv_file
        Boolean write_to_dsdb
        String backend
        String zones
        Int preemptible
        String docker_registry
        Int awsMaxRetries
        String config_version
    }

    command <<<

        python <<CODE

        import pandas as pd

        samplesheet = pd.read_csv("~{input_csv_file}", header = 0, dtype = str, index_col = False)
        samplesheet.columns = samplesheet.columns.str.strip()

        if "DataType" not in samplesheet.columns:
            samplesheet["DataType"] = "rna"
        else:
            samplesheet.loc[samplesheet["DataType"].isna(), "DataType"] = "rna"

        if "~{write_to_dsdb}" == "true":
            if ("Sample" in samplesheet.columns) and ("Library" in samplesheet.columns):
                samplesheet[["Sample", "Library", "DataType"]].to_csv("mapping.csv", index=False)
            else:
                raise Exception("If writing to DataSetDB, columns 'Sample' and 'Library' are both required!")

            if samplesheet["Reference"].nunique() == 1:
                with open("common_reference.txt", 'w') as fout:
                    fout.write(samplesheet["Reference"][0] + '\n')
            else:
                raise Exception("If writing to DataSetDB, all libraries must have an identical genome reference!")
        else:
            if "Library" not in samplesheet.columns:
                raise Exception("Column 'Library' is required in the sample sheet!")

        df_cellranger = samplesheet.copy()
        if "Sample" in df_cellranger.columns:
            df_cellranger.drop(columns=["Sample"], inplace=True)
        df_cellranger.rename(columns={"Library": "Sample"}, inplace=True)
        df_cellranger.to_csv("cellranger_sample_sheet.csv", index=False)

        CODE
    >>>

    output {
        File cellranger_sample_sheet = "cellranger_sample_sheet.csv"
        File? map_file = "mapping.csv"
        String? genome = read_string("common_reference.txt")
    }

    runtime {
        docker: "~{docker_registry}/config:~{config_version}"
        zones: zones
        preemptible: preemptible
        maxRetries: if backend == "aws" then awsMaxRetries else 0
    }
}
