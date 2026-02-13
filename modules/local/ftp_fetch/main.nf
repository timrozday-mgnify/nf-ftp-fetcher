process FTP_FETCH {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/gnu-wget:1.18--h36e9172_9' :
        'quay.io/biocontainers/gnu-wget:1.18--h36e9172_9' }"

    input:
    tuple val(meta), val(url)
    val(checksum)
    val(checksum_url)

    output:
    tuple val(meta), path("*.downloaded"), emit: file
    tuple val(meta), path("*.log")       , emit: log
    tuple val(meta), val(success)        , emit: status
    path "versions.yml"                  , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    success = true
    """
    # Placeholder — will be implemented with wget FTP download logic
    touch ${prefix}.downloaded
    touch ${prefix}.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        wget: \$(wget --version 2>&1 | head -1 | sed 's/GNU Wget //' | sed 's/ .*//')
    END_VERSIONS
    """
}
