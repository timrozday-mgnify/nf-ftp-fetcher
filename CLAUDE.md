# nf-ftp-fetcher

## Project Overview

A standalone Nextflow DSL2 module for fetching files over FTP with robust handling of unreliable connections. Follows nf-core guidelines for module structure and conventions.

## Environment

- **Nextflow version**: 25.10.x (DSL2)
- **Conda environment**: `nf-core` (activate via miniforge3: `/Users/timrozday/miniforge3/bin/conda`)
- **Key tools in env**: nextflow 25.10.2, nf-core 3.5.1, nf-test 0.9.2, openjdk 17
- **Run commands with**: `/Users/timrozday/miniforge3/bin/conda run -n nf-core <command>`

## Project Structure

```
nf-ftp-fetcher/
├── CLAUDE.md                    # This file
├── README.md                    # Project readme
├── main.nf                      # Entry workflow (test harness for the module)
├── nextflow.config              # Main Nextflow config
├── nf-test.config               # nf-test configuration
├── modules.json                 # nf-core module registry
├── .nf-core.yml                 # nf-core tool config & lint overrides
├── .gitignore
├── .pre-commit-config.yaml      # Pre-commit hooks (prettier, trailing whitespace)
├── .prettierrc.yml              # Prettier config
├── .prettierignore
├── conf/
│   ├── base.config              # Resource labels (process_single, etc.)
│   ├── modules.config           # Per-module ext.args and publishDir
│   └── test.config              # Test profile settings
├── modules/
│   └── local/
│       └── ftp_fetch/
│           ├── main.nf          # FTP_FETCH process definition
│           ├── environment.yml  # Conda deps (wget, coreutils)
│           └── meta.yml         # Module documentation
├── bin/                         # Custom scripts (auto-added to PATH in processes)
└── tests/
    ├── nextflow.config          # Shared test config
    └── modules/
        └── local/
            └── ftp_fetch/
                ├── main.nf.test      # nf-test tests
                └── nextflow.config   # Test-specific config
```

## Module Design: FTP_FETCH

### Core Features
- **FTP download via wget**: Uses `wget` for downloading files over FTP
- **Resume support**: `wget --continue` for resuming interrupted downloads
- **Retry logic**: Configurable retries with wait periods between attempts (`wget --tries`, `--waitretry`)
- **Checksum verification**: Supports checksum validation via:
  - A checksum URL (fetched and compared)
  - A direct checksum string
- **Check command**: Optional post-download validation script (from `bin/` directory)
- **Retry on check failure**: Re-download if the check command fails
- **Soft failure mode**: Option to return empty files + exit code 0 instead of erroring, allowing downstream pipeline handling

### Process Input/Output Design

**Inputs:**
- `tuple val(meta), val(url)` — meta map with sample ID + FTP URL string
- `val(checksum)` — optional checksum string (e.g., `md5:abc123...`)
- `val(checksum_url)` — optional URL to fetch checksum from

**Outputs:**
- `tuple val(meta), path("*.downloaded"), emit: file` — downloaded file(s)
- `tuple val(meta), path("*.log"), emit: log` — download log
- `tuple val(meta), val(success), emit: status` — boolean success status
- `path "versions.yml", emit: versions`

### Configuration (via ext.args or process params)
- `max_retries` — number of wget retry attempts (default: 3)
- `wait_retry` — seconds to wait between retries (default: 10)
- `timeout` — connection timeout in seconds (default: 60)
- `continue_download` — resume partial downloads (default: true)
- `check_command` — script name in bin/ to run for validation
- `retry_on_check_fail` — re-download if check command fails (default: false)
- `soft_fail` — return empty files + exit 0 on failure (default: false)

## Nextflow DSL2 Conventions

### Process Naming
- Process names: ALL_UPPERCASE with underscores (e.g., `FTP_FETCH`)
- File names: lowercase

### nf-core Patterns
- Always use `meta` map pattern as first element in tuple channels
- Use `task.ext.args` for injectable arguments
- Use `task.ext.prefix` for output file prefix (fallback: `meta.id`)
- Use `task.ext.when` for conditional execution
- Report tool versions in `versions.yml`
- Use nf-core label conventions (`process_single`, `process_low`, etc.)
- Container directive pattern supporting both Docker and Singularity
- Conda directive referencing `${moduleDir}/environment.yml`

### Script Conventions
- Scripts in `bin/` must have shebang lines and be executable (`chmod +x`)
- Use `#!/usr/bin/env bash` for portability
- Escape `$` in Nextflow script blocks for shell variables: `\$var`
- Use `\\` for line continuation in Nextflow script strings

## Testing

### Running All Tests
```bash
/Users/timrozday/miniforge3/bin/conda run -n nf-core nf-test test
```

### Running Module Tests
```bash
/Users/timrozday/miniforge3/bin/conda run -n nf-core nf-test test tests/modules/local/ftp_fetch/main.nf.test
```

### Updating Snapshots
```bash
/Users/timrozday/miniforge3/bin/conda run -n nf-core nf-test test tests/modules/local/ftp_fetch/main.nf.test --update-snapshot
```

### Running Nextflow Directly
```bash
/Users/timrozday/miniforge3/bin/conda run -n nf-core nextflow run main.nf -profile test,conda
```

## wget Key Flags for FTP

| Flag | Purpose |
|------|---------|
| `--continue` / `-c` | Resume partial downloads |
| `--tries=N` | Number of retry attempts |
| `--waitretry=S` | Wait S seconds between retries |
| `--timeout=S` | Set all timeout values |
| `--retry-connrefused` | Retry even on connection refused |
| `--no-passive-ftp` | Disable passive FTP if needed |
| `-O filename` | Write output to specific filename |
| `--progress=bar:force` | Force progress bar display |
| `-q` | Quiet mode (suppress output) |

## Code Style
- Groovy/Nextflow: 4-space indentation
- Shell scripts: 4-space indentation, use `set -euo pipefail`
- YAML: 2-space indentation
- Keep processes focused — one logical task per process
- Prefer `def` for local variables in Nextflow script blocks
