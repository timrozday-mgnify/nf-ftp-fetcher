#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MGnify/nf-ftp-fetcher
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/MGnify/nf-ftp-fetcher
----------------------------------------------------------------------------------------
*/

include { FTP_FETCH_FASTP } from './modules/local/ftp_fetch_fastp/main'

workflow {

    // Validate input parameter
    if (!params.input) {
        error "Please provide a samplesheet CSV via --input"
    }

    // Parse samplesheet into channel
    ch_reads = Channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true)
        .map { row ->
            def meta = [id: row.sample, single_end: row.single_end.toBoolean()]
            def urls = meta.single_end ? row.fastq_1 : [row.fastq_1, row.fastq_2]
            def adapter = params.adapter_fasta ? file(params.adapter_fasta) : []
            [meta, urls, adapter]
        }

    FTP_FETCH_FASTP(
        ch_reads,
        params.discard_trimmed_pass,
        params.save_trimmed_fail,
        params.save_merged,
        params.max_retries,
        params.wait_retry,
        params.timeout,
        params.resume_download,
        params.soft_fail
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
