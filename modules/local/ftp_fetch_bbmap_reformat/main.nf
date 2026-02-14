process FTP_FETCH_BBMAP_REFORMAT {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bbmap:39.15--h92535d8_0' :
        'biocontainers/bbmap:39.15--h92535d8_0' }"

    input:
    tuple val(meta), val(urls)
    val   out_fmt
    val   max_retries
    val   wait_retry
    val   timeout
    val   resume
    val   soft_fail

    output:
    tuple val(meta), path("*_reformated.${out_fmt}"), optional:true, emit: reformated
    tuple val(meta), path('*.reformat.sh.log')       , optional:true, emit: log
    tuple val(meta), path('*.download.log')          , emit: download_log
    tuple val(meta), path('*.status')                , emit: status
    tuple val("${task.process}"), val('bbmap'), eval('bbversion.sh 2>&1 | grep -v "Duplicate cpuset"'), emit: versions_bbmap, topic: versions
    tuple val("${task.process}"), val('wget'),  eval('wget --version 2>&1 | head -1 | sed -e "s/GNU Wget //;s/ .*//"'), emit: versions_wget, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    // Build wget flags
    def wget_continue = resume ? '--continue' : ''
    def wget_flags = "--tries=${max_retries} --waitretry=${wait_retry} --timeout=${timeout} --retry-connrefused ${wget_continue}"

    // Single URL only
    def url_list = urls instanceof List ? urls : [urls]
    def url1 = url_list[0]

    // Derive download filename from URL to preserve extension for format detection
    def url_basename = url1.tokenize('?')[0].tokenize('/')[-1]
    def dl_file1 = "${prefix}.${url_basename}"

    // Soft fail empty file creation
    def empty_reformated = "echo '' | gzip > ${prefix}_reformated.${out_fmt}"

    """
    #!/usr/bin/env bash
    set -euo pipefail

    PREFIX="${prefix}"
    MAX_RETRIES="${max_retries}"
    WAIT_RETRY="${wait_retry}"
    SOFT_FAIL="${soft_fail}"
    URL1="${url1}"
    DL_FILE1="${dl_file1}"
    WGET_FLAGS="${wget_flags}"
    OUT_FMT="${out_fmt}"
    DOWNLOAD_LOG="\${PREFIX}.download.log"

    BBMAP_ARGS="${args}"

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

        if [ "\${DOWNLOAD_OK}" = "false" ]; then
            echo "Download failed on attempt \${attempt}" >> "\${DOWNLOAD_LOG}"
            rm -f "\${DL_FILE1}"
            if [ "\${attempt}" -lt "\${MAX_RETRIES}" ]; then
                echo "Sleeping \${WAIT_RETRY}s before next attempt..." >> "\${DOWNLOAD_LOG}"
                sleep "\${WAIT_RETRY}"
            fi
            continue
        fi

        echo "Download succeeded, running reformat.sh..." >> "\${DOWNLOAD_LOG}"

        # --- Run reformat.sh ---
        TOOL_OK=true

        if ! reformat.sh \\
            in="\${DL_FILE1}" \\
            out="\${PREFIX}_reformated.\${OUT_FMT}" \\
            uniquenames=t \\
            trimreaddescription=t \\
            \${BBMAP_ARGS} \\
            2> >(tee "\${PREFIX}.reformat.sh.log" >&2); then
            TOOL_OK=false
        fi

        if [ "\${TOOL_OK}" = "true" ]; then
            echo "reformat.sh succeeded on attempt \${attempt}" >> "\${DOWNLOAD_LOG}"
            SUCCESS=true
            break
        else
            echo "reformat.sh failed on attempt \${attempt}" >> "\${DOWNLOAD_LOG}"
            # Clean up tool outputs before retry
            rm -f "\${PREFIX}_reformated.\${OUT_FMT}"
            rm -f "\${PREFIX}.reformat.sh.log"
            # Clean up downloaded files so wget starts fresh
            rm -f "\${DL_FILE1}"
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
            ${empty_reformated}
            touch "\${PREFIX}.reformat.sh.log"
        else
            exit 1
        fi
    fi
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo '' | gzip > ${prefix}_reformated.${out_fmt}
    touch "${prefix}.reformat.sh.log"
    touch "${prefix}.download.log"
    echo "true" > ${prefix}.status
    """
}
