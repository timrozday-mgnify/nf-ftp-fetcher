process FASTP {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/52/527b18847a97451091dba07a886b24f17f742a861f9f6c9a6bfb79d4f1f3bf9d/data' :
        'community.wave.seqera.io/library/fastp:1.0.1--c8b87fe62dcc103c' }"

    input:
    tuple val(meta), val(urls), path(adapter_fasta)
    val   discard_trimmed_pass
    val   save_trimmed_fail
    val   save_merged
    val   max_retries
    val   wait_retry
    val   timeout
    val   resume
    val   soft_fail

    output:
    tuple val(meta), path('*.fastp.fastq.gz') , optional:true, emit: reads
    tuple val(meta), path('*.json')           , optional:true, emit: json
    tuple val(meta), path('*.html')           , optional:true, emit: html
    tuple val(meta), path('*.fastp.log')      , optional:true, emit: log
    tuple val(meta), path('*.fail.fastq.gz')  , optional:true, emit: reads_fail
    tuple val(meta), path('*.merged.fastq.gz'), optional:true, emit: reads_merged
    tuple val(meta), path('*.download.log')   , emit: download_log
    tuple val(meta), path('*.status')         , emit: status
    tuple val("${task.process}"), val('fastp'), eval('fastp --version 2>&1 | sed -e "s/fastp //g"'), emit: versions_fastp, topic: versions
    tuple val("${task.process}"), val('wget'),  eval('wget --version 2>&1 | head -1 | sed -e "s/GNU Wget //;s/ .*//"'), emit: versions_wget, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def adapter_list = adapter_fasta ? "--adapter_fasta ${adapter_fasta}" : ""
    def fail_fastq = save_trimmed_fail && meta.single_end ? "--failed_out ${prefix}.fail.fastq.gz" : save_trimmed_fail && !meta.single_end ? "--failed_out ${prefix}.paired.fail.fastq.gz --unpaired1 ${prefix}_R1.fail.fastq.gz --unpaired2 ${prefix}_R2.fail.fastq.gz" : ''
    def out_fq1 = discard_trimmed_pass ?: ( meta.single_end ? "--out1 ${prefix}.fastp.fastq.gz" : "--out1 ${prefix}_R1.fastp.fastq.gz" )
    def out_fq2 = discard_trimmed_pass ?: "--out2 ${prefix}_R2.fastp.fastq.gz"
    def merge_fastq = save_merged && !meta.single_end ? "-m --merged_out ${prefix}.merged.fastq.gz" : ''
    def is_interleaved = task.ext.args?.contains('--interleaved_in') ? 'true' : 'false'
    def is_single = meta.single_end ? 'true' : 'false'

    // Build wget flags
    def wget_continue = resume ? '--continue' : ''
    def wget_flags = "--tries=${max_retries} --waitretry=${wait_retry} --timeout=${timeout} --retry-connrefused ${wget_continue}"

    // Determine URL list and download targets
    def url_list = urls instanceof List ? urls : [urls]
    def url1 = url_list[0]
    def url2 = url_list.size() > 1 ? url_list[1] : ''

    // Download filenames
    def dl_file1 = is_interleaved == 'true' || is_single == 'true' ? "${prefix}.fastq.gz" : "${prefix}_R1.fastq.gz"
    def dl_file2 = "${prefix}_R2.fastq.gz"

    // Soft fail empty file creation commands (computed in Groovy for correct branching)
    def empty_reads = ''
    if (!discard_trimmed_pass) {
        if (task.ext.args?.contains('--interleaved_in') || meta.single_end) {
            empty_reads = "echo '' | gzip > ${prefix}.fastp.fastq.gz"
        } else {
            empty_reads = "echo '' | gzip > ${prefix}_R1.fastp.fastq.gz ; echo '' | gzip > ${prefix}_R2.fastp.fastq.gz"
        }
    }
    def empty_fail = ''
    if (save_trimmed_fail) {
        if (meta.single_end) {
            empty_fail = "echo '' | gzip > ${prefix}.fail.fastq.gz"
        } else {
            empty_fail = "echo '' | gzip > ${prefix}.paired.fail.fastq.gz ; echo '' | gzip > ${prefix}_R1.fail.fastq.gz ; echo '' | gzip > ${prefix}_R2.fail.fastq.gz"
        }
    }
    def empty_merged = save_merged && !meta.single_end ? "echo '' | gzip > ${prefix}.merged.fastq.gz" : ''

    """
    #!/usr/bin/env bash
    set -euo pipefail

    PREFIX="${prefix}"
    MAX_RETRIES="${max_retries}"
    WAIT_RETRY="${wait_retry}"
    IS_INTERLEAVED="${is_interleaved}"
    IS_SINGLE="${is_single}"
    SOFT_FAIL="${soft_fail}"
    URL1="${url1}"
    URL2="${url2}"
    DL_FILE1="${dl_file1}"
    DL_FILE2="${dl_file2}"
    WGET_FLAGS="${wget_flags}"
    DOWNLOAD_LOG="\${PREFIX}.download.log"

    # fastp arguments (interpolated from Groovy)
    ADAPTER_LIST="${adapter_list}"
    FAIL_FASTQ="${fail_fastq}"
    OUT_FQ1="${out_fq1}"
    OUT_FQ2="${out_fq2}"
    MERGE_FASTQ="${merge_fastq}"
    FASTP_ARGS="${args}"

    SUCCESS=false

    : > "\${DOWNLOAD_LOG}"

    for attempt in \$(seq 1 \${MAX_RETRIES}); do
        echo "=== Attempt \${attempt}/\${MAX_RETRIES} ===" >> "\${DOWNLOAD_LOG}"
        echo "Started: \$(date -Iseconds)" >> "\${DOWNLOAD_LOG}"

        # --- Download ---
        DOWNLOAD_OK=true

        echo "Downloading \${URL1} -> \${DL_FILE1}" >> "\${DOWNLOAD_LOG}"
        if ! wget \${WGET_FLAGS} -O "\${DL_FILE1}" "\${URL1}" >> "\${DOWNLOAD_LOG}" 2>&1; then
            echo "Download failed for \${URL1}" >> "\${DOWNLOAD_LOG}"
            DOWNLOAD_OK=false
        fi

        if [ "\${DOWNLOAD_OK}" = "true" ] && [ -n "\${URL2}" ]; then
            echo "Downloading \${URL2} -> \${DL_FILE2}" >> "\${DOWNLOAD_LOG}"
            if ! wget \${WGET_FLAGS} -O "\${DL_FILE2}" "\${URL2}" >> "\${DOWNLOAD_LOG}" 2>&1; then
                echo "Download failed for \${URL2}" >> "\${DOWNLOAD_LOG}"
                DOWNLOAD_OK=false
            fi
        fi

        if [ "\${DOWNLOAD_OK}" = "false" ]; then
            echo "Download failed on attempt \${attempt}" >> "\${DOWNLOAD_LOG}"
            rm -f "\${DL_FILE1}" "\${DL_FILE2}"
            if [ "\${attempt}" -lt "\${MAX_RETRIES}" ]; then
                echo "Sleeping \${WAIT_RETRY}s before next attempt..." >> "\${DOWNLOAD_LOG}"
                sleep "\${WAIT_RETRY}"
            fi
            continue
        fi

        echo "Download succeeded, running fastp..." >> "\${DOWNLOAD_LOG}"

        # --- Run fastp ---
        FASTP_OK=true

        if [ "\${IS_INTERLEAVED}" = "true" ]; then
            if ! fastp \\
                --stdout \\
                --in1 "\${DL_FILE1}" \\
                --thread ${task.cpus} \\
                --json "\${PREFIX}.fastp.json" \\
                --html "\${PREFIX}.fastp.html" \\
                \${ADAPTER_LIST} \\
                \${FAIL_FASTQ} \\
                \${FASTP_ARGS} \\
                2> >(tee "\${PREFIX}.fastp.log" >&2) \\
            | gzip -c > "\${PREFIX}.fastp.fastq.gz"; then
                FASTP_OK=false
            fi
        elif [ "\${IS_SINGLE}" = "true" ]; then
            if ! fastp \\
                --in1 "\${DL_FILE1}" \\
                \${OUT_FQ1} \\
                --thread ${task.cpus} \\
                --json "\${PREFIX}.fastp.json" \\
                --html "\${PREFIX}.fastp.html" \\
                \${ADAPTER_LIST} \\
                \${FAIL_FASTQ} \\
                \${FASTP_ARGS} \\
                2> >(tee "\${PREFIX}.fastp.log" >&2); then
                FASTP_OK=false
            fi
        else
            if ! fastp \\
                --in1 "\${DL_FILE1}" \\
                --in2 "\${DL_FILE2}" \\
                \${OUT_FQ1} \\
                \${OUT_FQ2} \\
                --json "\${PREFIX}.fastp.json" \\
                --html "\${PREFIX}.fastp.html" \\
                \${ADAPTER_LIST} \\
                \${FAIL_FASTQ} \\
                \${MERGE_FASTQ} \\
                --thread ${task.cpus} \\
                --detect_adapter_for_pe \\
                \${FASTP_ARGS} \\
                2> >(tee "\${PREFIX}.fastp.log" >&2); then
                FASTP_OK=false
            fi
        fi

        if [ "\${FASTP_OK}" = "true" ]; then
            echo "fastp succeeded on attempt \${attempt}" >> "\${DOWNLOAD_LOG}"
            SUCCESS=true
            break
        else
            echo "fastp failed on attempt \${attempt}" >> "\${DOWNLOAD_LOG}"
            # Clean up fastp outputs before retry
            rm -f "\${PREFIX}.fastp.json" "\${PREFIX}.fastp.html" "\${PREFIX}.fastp.log"
            rm -f "\${PREFIX}.fastp.fastq.gz" "\${PREFIX}_R1.fastp.fastq.gz" "\${PREFIX}_R2.fastp.fastq.gz"
            rm -f "\${PREFIX}.fail.fastq.gz" "\${PREFIX}.paired.fail.fastq.gz" "\${PREFIX}_R1.fail.fastq.gz" "\${PREFIX}_R2.fail.fastq.gz"
            rm -f "\${PREFIX}.merged.fastq.gz"
            # Clean up downloaded files so wget starts fresh
            rm -f "\${DL_FILE1}" "\${DL_FILE2}"
            if [ "\${attempt}" -lt "\${MAX_RETRIES}" ]; then
                echo "Sleeping \${WAIT_RETRY}s before next attempt..." >> "\${DOWNLOAD_LOG}"
                sleep "\${WAIT_RETRY}"
            fi
        fi
    done

    # Write status
    echo "\${SUCCESS}" > "\${PREFIX}.status"

    if [ "\${SUCCESS}" = "false" ]; then
        echo "All \${MAX_RETRIES} attempts failed" >> "\${DOWNLOAD_LOG}"
        if [ "\${SOFT_FAIL}" = "true" ]; then
            echo "Soft fail mode: creating empty output files" >> "\${DOWNLOAD_LOG}"
            ${empty_reads}
            ${empty_fail}
            ${empty_merged}
            touch "\${PREFIX}.fastp.json"
            touch "\${PREFIX}.fastp.html"
            touch "\${PREFIX}.fastp.log"
            exit 0
        else
            exit 1
        fi
    fi
    """

    stub:
    def prefix              = task.ext.prefix ?: "${meta.id}"
    def is_single_output    = task.ext.args?.contains('--interleaved_in') || meta.single_end
    def touch_reads         = (discard_trimmed_pass) ? "" : (is_single_output) ? "echo '' | gzip > ${prefix}.fastp.fastq.gz" : "echo '' | gzip > ${prefix}_R1.fastp.fastq.gz ; echo '' | gzip > ${prefix}_R2.fastp.fastq.gz"
    def touch_merged        = (!is_single_output && save_merged) ? "echo '' | gzip >  ${prefix}.merged.fastq.gz" : ""
    def touch_fail_fastq    = (!save_trimmed_fail) ? "" : meta.single_end ? "echo '' | gzip > ${prefix}.fail.fastq.gz" : "echo '' | gzip > ${prefix}.paired.fail.fastq.gz ; echo '' | gzip > ${prefix}_R1.fail.fastq.gz ; echo '' | gzip > ${prefix}_R2.fail.fastq.gz"
    """
    $touch_reads
    $touch_fail_fastq
    $touch_merged
    touch "${prefix}.fastp.json"
    touch "${prefix}.fastp.html"
    touch "${prefix}.fastp.log"
    touch "${prefix}.download.log"
    echo "true" > ${prefix}.status
    """
}
