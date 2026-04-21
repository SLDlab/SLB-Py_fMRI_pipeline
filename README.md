# FitLins fMRI Analysis Pipeline

GLM-based fMRI analysis pipeline for the SLB dataset, built around FitLins and a patched Apptainer container. The pipeline runs subject-level and group-level analyses from preprocessed fMRIPrep outputs through to thresholded statistical maps, patched HTML reports, user-facing PDF reports, and per-task-group analysis indexes.

---

## Prerequisites

Before running any analysis, three things must exist on disk:

1. A working BIDS directory (`slb_bids_runs/`) — thin clone of the shared BIDS data
2. The patched Apptainer container (`fitlins-0.11.0_pybids-0.15.6_patched.sif`)
3. An events directory (`slb_events/`) — only required for models that use non-default events (e.g. motor models)

Setup instructions for each are in the [One-time setup](#one-time-setup) section below.

---

## Directory layout

The pipeline separates **shared data** (read-only) from **user workspaces** (writable).
Each user works inside their own 'slb_work/' directory.

### Shared directory
```
analysis_work/
  slb_bids_runs/            Working BIDS directory (symlinked NIfTIs, local metadata)
  slb_events/
    original/               Reference copies of events TSVs from slb_bids_runs
    motor/                  Augmented events with button press delta events added
  fitlins_models/           Model JSON files (*_smdl.json), one per analysis
  fitlins_configs/          Config files (*. cfg), one per analysis
  fitlins_derivatives/      FitLins outputs (statmaps, reports)
  figures/                  Thresholded statistical maps (PNG) and manifests
  reports/                  Generated PDF model reports, namespaced by task group
  docs/
    dictionaries/           CSV data dictionaries used by event-building scripts
    indexes/                Per-task-group analysis indexes (.md + .json)
  slurm_logs/               SLURM sbatch scripts and job logs
  scripts/
    build/                  Data preparation scripts (run once before analysis)
    run/                    Pipeline execution scripts (main entry points)
    report/                 PDF report and analysis index generators
    setup/                  User environment initial setup
    validate/               Validation scripts
.slb_global_env             Global environment
```
### User directory
```
slb_work/
  slb_bids_runs/            Working BIDS directory (symlinked NIfTIs, local metadata)
  slb_events/
    original/               Reference copies of events TSVs from slb_bids_runs
    motor/                  Augmented events with button press delta events added
  fitlins_models/           User run Model JSON files (*_smdl.json), one per analysis
  fitlins_configs/          User run Config files (*. cfg), one per analysis
  fitlins_derivatives/      User run FitLins outputs (statmaps, reports)
  figures/                  Thresholded statistical maps (PNG) and manifests
  reports/                  Generated PDF model reports, namespaced by task group
  slurm_logs/               SLURM sbatch scripts and job logs
.slb_user_env               user environment
```



---

## Scripts

**`scripts/setup/`** — data preparation, run once before analysis

| Script                                                                                                 | Purpose                                                                         |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| `slb-analysis-init.sh`                                                                       | Initialize user workspace (create env, venv, directories, configs/models, and BIDS thin clone)       |


**`scripts/build/`** — data preparation, run once before analysis

| Script                                                                                                 | Purpose                                                                         |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| `rebuild_bids_runs_thinclone.py`                                                                       | Create the working BIDS directory (symlink NIfTIs, copy metadata locally)       |
| `init_events_dir.sh`                                                                                   | Initialize the `slb_events/` directory structure                                |
| `add_tmth_button_press_events.py` / `add_ol_button_press_events.py` / `add_sra_button_press_events.py` | Generate motor events TSVs with button press delta events (one script per task) |

**`scripts/run/`** — pipeline execution

| Script                   | Purpose                                                                       |
| ------------------------ | ----------------------------------------------------------------------------- |
| `run_pipeline.sh`        | **Main entry point.** Orchestrates FitLins → report fix → plotting → optional PDF report generation |
| `submit_pipeline.sh`     | SLURM wrapper for `run_pipeline.sh`                                           |
| `run_fitlins_models.sh`  | Low-level FitLins runner inside the container (called by `run_pipeline.sh`)   |
| `parse_model.py`         | Parse a model JSON to extract subjects, contrasts, nodes, stat type           |
| `fix_fitlins_reports.py` | Post-hoc patcher for FitLins HTML reports                                     |
| `plot_fmri_statmaps.py`  | Nilearn-based stat map plotter (glass brain, slices, 3D HTML, cluster tables) |

**`scripts/report/`** — reporting and indexing

| Script                      | Purpose                                                                 |
| --------------------------- | ----------------------------------------------------------------------- |
| `generate_model_report.py`  | Build PDF reports from FitLins outputs, manifests, and run-report figures |
| `build_analysis_index.py`   | Build per-task-group analysis indexes in Markdown and JSON              |

**`scripts/validate/`** — validation

`fitlins_patched.def` (container definition file) lives in `containers/fitlins_patched/` alongside `environment.yml`.

---

## One-time setup

This pipeline uses a shared (read-only) + user (writable) architecture.
- Shared resources are maintained centrally (analysis_work/)
- Each user initializes their own workspace once

---

## Shared setup (Pre-configured and centrally maintained)

### 1. Shared BIDS dataset : `/data/sld/homes/collab/slb/bids_runs`

The shared BIDS data is read-only. This script creates a local working copy by symlinking NIfTI files and copying all metadata (JSON, TSV) so they can be edited without affecting the shared source.

```bash
python3 rebuild_bids_runs_thinclone.py \
  --src /data/sld/homes/collab/slb/bids_runs \
  --dst  "$SLB_USER_BIDS_DIR"
```

### 2. fMRIPrep outputs :  `/data/sld/homes/collab/slb/derivatives/fmriprep_runs`

### 3. Patched FitLins container :  `analysis_work/containers/fitlins_patched/fitlins-0.11.0_pybids-0.15.6_patched.sif`

```bash
cd containers/fitlins_patched/
apptainer build fitlins_patched.sif fitlins_patched.def
mv -n fitlins_patched.sif fitlins-0.11.0_pybids-0.15.6_patched.sif

# Optional checksum for reproducibility records
sha256sum fitlins-0.11.0_pybids-0.15.6_patched.sif > fitlins-0.11.0_pybids-0.15.6_patched.sif.sha256
```

The container is required because vanilla FitLins fails on this dataset with a `NotImplementedError` on dict-valued PyBIDS entities. The patched container applies a fix at the source level and pins `fitlins==0.11.0`, `pybids==0.15.6`, `pandas==1.5.*`, and `nilearn==0.9.2`.

Only rebuild the container if `fitlins_patched.def` changes.

### 4. Pipeline codebase  :  `analysis_work/`

Users should **not modify any of the above**

---

## User setup (Run once)

Each user must initialize their personal workspace.

### 1. Load the shared environment

```bash
source /data/sld/homes/collab/slb/.slb_global_env
```

### 2. Configure user workspace

#### 2a. Initialize your workspace

```bash
bash $SLB_ANALYSIS_ROOT/scripts/setup/slb-analysis-init.sh
```
This will automatically:

- create your user environment file (~/.slb_user_env)
- create your working directory (slb_work/)
- set up a Python virtual environment
- install required Python packages
- copy configs and models into your workspace
- build a thin-clone BIDS directory (slb_bids_runs/)

To reset everything
```bash
bash $SLB_ANALYSIS_ROOT/scripts/setup/slb-analysis-init.sh --force
```

#### 2b. Activate your environment
```bash
source /data/sld/homes/$USER/.slb_user_env
module use /software/sld/modulefiles
module load python/3.12.8
source $SLB_USER_ROOT/venv/bin/activate
```

### 3. Initialize the events directory (non-standard events only)

Standard visual models use the events TSVs already in `slb_bids_runs` and do not need this step. Models that require augmented events (e.g. motor models with button press delta events) use a separate `slb_events/` directory so the BIDS source is never modified.

#### 3a. Initialize the directory structure (once)

Run this once before generating any augmented events. It creates `slb_events/original/` (a verbatim reference copy of all events TSVs) and the named subdirectory that will hold the augmented versions.

```bash
bash  $SLB_ANALYSIS_ROOT/scripts/build/init_events_dir.sh \
  --bids-dir   "$SLB_USER_BIDS_DIR" \
  --events-dir "$SLB_USER_EVENTS_DIR" \
  --name motor
```

`slb_events/original/` is never modified after this point. `slb_events/motor/` will hold the augmented TSVs. If the source events change (e.g. after re-preprocessing), delete both subdirectories and re-run from scratch.

#### 3b. Generate augmented events

Each task has its own script that reads from `slb_events/original/` and writes augmented TSVs to `slb_events/motor/`. Always do a dry run first to verify the output before writing files.

**tmth** (`task-tm`, `task-th`) — button press onset derived from `scannerTimer_choice_Start + choice_RTs`:

```bash
# Run with --dry-run for testing
python3 $SLB_ANALYSIS_ROOT/scripts/build/add_tmth_button_press_events.py \
  --src-bids-dir   "$SLB_USER_EVENTS_DIR/original" \
  --dst-events-dir "$SLB_USER_EVENTS_DIR/motor" \
  --tasks tm th --dry-run

# Run without --dry-run when satisfied
python3 $SLB_ANALYSIS_ROOT/scripts/build/add_tmth_button_press_events.py \
  --src-bids-dir   "$SLB_USER_EVENTS_DIR/original" \
  --dst-events-dir "$SLB_USER_EVENTS_DIR/motor" \
  --tasks tm th
```

**OL** (`task-obslearn`) — button press onset derived from `scannerTimer_self_choice_Start + choice_RT`:

```bash
# Run with --dry-run for testing
python3 $SLB_ANALYSIS_ROOT/scripts/build/add_ol_button_press_events.py \
  --src-bids-dir   "$SLB_USER_EVENTS_DIR/original" \
  --dst-events-dir "$SLB_USER_EVENTS_DIR/motor" \
  --tasks obslearn --dry-run

# Run without --dry-run when satisfied
python3 $SLB_ANALYSIS_ROOT/scripts/build/add_ol_button_press_events.py \
  --src-bids-dir   "$SLB_USER_EVENTS_DIR/original" \
  --dst-events-dir "$SLB_USER_EVENTS_DIR/motor" \
  --tasks obslearn
```

**SRA** (`task-riskself`) — button press onset derived from `onset of self_choice row + self_RT`:

```bash
# Run with --dry-run for testing
python3 $SLB_ANALYSIS_ROOT/scripts/build/add_sra_button_press_events.py \
  --src-bids-dir   "$SLB_USER_EVENTS_DIR/original" \
  --dst-events-dir "$SLB_USER_EVENTS_DIR/motor" \
  --tasks riskself --dry-run

# Run without --dry-run when satisfied
python3 $SLB_ANALYSIS_ROOT/scripts/build/add_sra_button_press_events.py \
  --src-bids-dir   "$SLB_USER_EVENTS_DIR/original" \
  --dst-events-dir "$SLB_USER_EVENTS_DIR/motor" \
  --tasks riskself
```

All three scripts add the same three delta event types per button press (`button_press`, `button_press_left`, `button_press_right`) and can be run independently — you do not need to generate all tasks at once.

### 4. Make shell scripts executable

The shell scripts will not have the executable bit set. Run this once:

```bash
chmod +x $SLB_ANALYSIS_ROOT/scripts/run/*.sh \
         $SLB_ANALYSIS_ROOT/scripts/build/*.sh
```

Alternatively, invoke scripts explicitly with `bash` (e.g. `bash run_pipeline.sh ...`) to bypass the need for the executable bit.

---

## Running an analysis

Before running any analysis, make sure the environment is activated.

### Step 1: Write a model JSON

Place it in `fitlins_models/` with the naming convention `<stem>_smdl.json`. The pipeline auto-derives subjects, contrasts, node names, and stat type from the model JSON at run time — you do not need to specify these in the config or on the command line.

### Step 2: Write a config file

Place it in `fitlins_configs/`. A config file is a sourced bash file that sets variables. CLI flags always override config values.

```bash
# -- Model -----------------------------------------------------------------
MODEL="my_model_stem"
# MODEL_JSON left unset -> resolves to ${MODELS_DIR}/${MODEL}_smdl.json

# -- Data paths ------------------------------------------------------------
# BIDS_DIR auto-resolves from environment (do not set)
# BIDS_DIR="/data/sld/homes/vguigon/work/slb_bids_runs"
# EVENTS_DIR: set this for motor models; leave unset for visual/standard models
# EVENTS_DIR="${SLB_USER_EVENTS_DIR}/motor"
DERIV_SUBDIR="fmriprep_runs"
DERIV_LABEL="fmriprep"

# -- FitLins ---------------------------------------------------------------
SMOOTH="4:run:iso"    # kernel in mm : level : type
NCPUS="8"
MEM_GB="16"
# SUBJECTS left unset -> auto-derived from model JSON

# -- Thresholding ----------------------------------------------------------
# Thresholding is visualization-only. FitLins always writes unthresholded
# .nii statmaps; thresholding happens in plot_fmri_statmaps.py only.
THR_MODE="p-unc"      # none | fixed | p-unc | fdr | bonferroni | ari
P_UNC="0.01"          # used when THR_MODE=p-unc
ALPHA="0.05"          # used when THR_MODE=fdr | bonferroni | ari
TWO_SIDED="1"         # 1 = two-sided (default); 0 = one-sided
CLUSTER_EXTENT="10"   # minimum cluster size in voxels; comment out to disable
#ARI_THRESHOLDS="2.5 3.0 3.5"   # cluster-forming z-thresholds for ari mode
#ROI_MASK=""                     # path to NIfTI mask for SVC; empty = whole-brain
#CLUSTER_TABLE="0"               # 1 = write TSV cluster summary alongside figures

# -- Rendering -------------------------------------------------------------
DISPLAY_MODE="ortho"  # ortho | x | y | z
PLOT_ABS="1"          # 1 = plot absolute values (both tails on same scale)
# --view3d at the command line generates interactive 3D HTML via Nilearn view_img

# -- SLURM -----------------------------------------------------------------
SLURM_PARTITION="compute"
SLURM_TIME=""
SLURM_MAIL_USER="you@umd.edu"
SLURM_MAIL_TYPE="END,FAIL"
```

### Step 3: Run

#### Without SLURM (login node)

```bash
# Full pipeline: FitLins -> fix report -> plot run-level -> plot group-level -> PDF report
$SLB_ANALYSIS_ROOT/scripts/run/run_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --steps all

# Rerun FitLins even if output directory already exists
$SLB_ANALYSIS_ROOT/scripts/run/run_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --steps all --force

# Plot only (FitLins already ran)
$SLB_ANALYSIS_ROOT/scripts/run/run_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --steps plot-run,plot-group

# Plot and generate the PDF report
$SLB_ANALYSIS_ROOT/scripts/run/run_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --steps plot-run,plot-group,report

# Plot with interactive 3D HTML viewers
$SLB_ANALYSIS_ROOT/scripts/run/run_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --steps plot-run,plot-group --view3d

# Override threshold at the command line
$SLB_ANALYSIS_ROOT/scripts/run/run_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --thr-mode fixed --thr-fixed 4.0
```

#### With SLURM

`submit_pipeline.sh` generates a timestamped sbatch script and submits it. All `run_pipeline.sh` flags pass through transparently. SLURM resources (`--cpus-per-task`, `--mem`) are taken from `NCPUS` and `MEM_GB` in your config.

```bash
# Submit full pipeline
$SLB_ANALYSIS_ROOT/scripts/run/submit_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --steps all

# Submit plotting plus PDF report generation
$SLB_ANALYSIS_ROOT/scripts/run/submit_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --steps plot-run,plot-group,report

# Inspect the sbatch script without submitting
$SLB_ANALYSIS_ROOT/scripts/run/submit_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --no-submit

# Print sbatch script to stdout only (nothing written or submitted)
$SLB_ANALYSIS_ROOT/scripts/run/submit_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --dry-run
```

Use SLURM for the `fitlins` step, which is CPU- and memory-intensive. Plotting steps (`plot-run`, `plot-group`) are lightweight and can run directly on the login node to avoid the ~5-minute SLURM overhead.

```bash
# Submit FitLins only
$SLB_ANALYSIS_ROOT/scripts/run/submit_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --steps fitlins

# Then plot directly once the job finishes
$SLB_ANALYSIS_ROOT/scripts/run/run_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --steps plot-run,plot-group

# Or plot and build the PDF report directly
$SLB_ANALYSIS_ROOT/scripts/run/run_pipeline.sh --config $SLB_USER_CONFIGS/my_model.cfg --steps plot-run,plot-group,report
```

---

## Pipeline steps

| Step         | What it does                                                                                                                                                              |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fitlins`    | Runs FitLins GLM inside the patched container                                                                                                                             |
| `fixreport`  | Patches the HTML report: fixes broken image paths and embeds all figures (design matrices, correlation matrices, contrast maps) as base64 so the report is self-contained |
| `plot-run`   | Plots run-level stat maps for all subjects                                                                                                                                |
| `plot-group` | Plots all group-level nodes; loops over multiple nodes automatically                                                                                                      |
| `report`     | Builds a PDF report under `reports/<task_group>/` via `scripts/report/generate_model_report.py`                                                                         |
| `all`        | All of the above in order                                                                                                                                                 |

Pass as comma-separated values to `--steps`. Default is `all`.

---

## Auto-derivation from model JSON

When not set in config or CLI, `run_pipeline.sh` derives these values automatically via `parse_model.py`:

| Variable      | Source in model JSON                                     |
| ------------- | -------------------------------------------------------- |
| `SUBJECTS`    | `Input.subject`                                          |
| `CONTRASTS`   | All `Contrasts[].Name` across all nodes                  |
| `STATS`       | `Test` field of the first explicit contrast (`t` or `z`) |
| `NODES_RUN`   | The node with `"Level": "Run"`                           |
| `GROUP_NODES` | All nodes with `"Level" != "Run"`                        |
| `PLOT_GLOB`   | `**/*stat-<STATS>*_statmap.nii*`                         |

`parse_model.py` can also be called directly for inspection:

```bash
python3 $SLB_ANALYSIS_ROOT/scripts/run/parse_model.py $SLB_USER_MODELS/my_model_smdl.json --field subjects
python3 $SLB_ANALYSIS_ROOT/scripts/run/parse_model.py $SLB_USER_MODELS/my_model_smdl.json --field contrasts
python3 $SLB_ANALYSIS_ROOT/scripts/run/parse_model.py $SLB_USER_MODELS/my_model_smdl.json --field group_nodes
```

---

## Thresholding

Thresholding is applied by `plot_fmri_statmaps.py` at visualization time and does not modify the `.nii` files on disk.

| `THR_MODE`   | Behaviour                                                                                              | Key parameters            |
| ------------ | ------------------------------------------------------------------------------------------------------ | ------------------------- |
| `p-unc`      | Uncorrected p-value converted to t/z statistic; df auto-inferred from design matrix or set with `--df` | `P_UNC`                   |
| `fixed`      | Fixed threshold applied directly to the stat map                                                       | `THR_FIXED`               |
| `fdr`        | Benjamini-Hochberg FDR via Nilearn `threshold_stats_img`; requires z-maps                              | `ALPHA`                   |
| `bonferroni` | Bonferroni FWER via Nilearn `threshold_stats_img`; requires z-maps                                     | `ALPHA`                   |
| `ari`        | All-Resolution Inference (Rosenblatt et al. 2018); produces proportion-of-true-discoveries image       | `ALPHA`, `ARI_THRESHOLDS` |
| `none`       | No threshold; all voxels displayed                                                                     | —                         |

`TWO_SIDED=1` (the default) splits alpha across both tails, so a nominal p=0.01 is applied as p=0.005 per tail. This results in a stricter threshold than one-sided at the same nominal level. The figure directory name encodes the sidedness (`_2s` or `_1s`) to distinguish outputs generated under different settings.

`CLUSTER_EXTENT` discards surviving clusters smaller than the specified number of voxels. Set `ROI_MASK` to a NIfTI file to restrict correction to a region of interest (SVC). Set `CLUSTER_TABLE=1` to write a TSV cluster summary alongside the figures.

---

## Fixing reports

FitLins generates an HTML report under `fitlins_derivatives/<model>/reports/`. The report contains design matrices, correlation matrices, and contrast figures, but the image paths it writes are relative to the container's internal filesystem and break when opened outside it. The `fixreport` step in `run_pipeline.sh` calls `fix_fitlins_reports.py` automatically, but you can also run it manually if needed:

```bash
python3 $SLB_ANALYSIS_ROOT/scripts/run/fix_fitlins_reports.py \
  $SLB_USER_OUT/fitlins_derivatives/<model>_s<kernel>/reports/model-*.html

# Verbose mode prints diagnostics for any figures that could not be resolved
python3 $SLB_ANALYSIS_ROOT/scripts/run/fix_fitlins_reports.py \
  $SLB_USER_OUT/fitlins_derivatives/<model>_s<kernel>/reports/model-*.html \
  --verbose
```

The script patches the report in place and writes a `.bak` backup alongside it. It does three things:

1. Rewrites broken `src`/`href` paths that reference the container's internal work directory
2. Embeds all local images (design matrices, correlation matrices, contrast figures) as base64 data URIs, making the report fully self-contained
3. Injects contrast figures found on disk into sections where FitLins reported them as missing due to `--drop-missing`

After patching, the report can be opened in any browser or via VSCode Live Server without broken images.

---

```
fitlins_derivatives/
  <model>_s<kernel>/           FitLins outputs
    node-<runNode>/
    node-<groupNode1>/
    ...
    reports/
      model-*.html             HTML report (patched in place by fixreport step)

figures/
  <model>_s<kernel>/
    <runNode>_<thr>_<side>/    Run-level figures
    <groupNode>_<thr>_<side>/  Group-level figures (one directory per node)
      <tag>__glass.png
      <tag>__slices.png
      <tag>__3d.html           (only when --view3d is passed)
      <tag>__clusters.tsv      (only when CLUSTER_TABLE=1)
      manifest.tsv
```

The figure directory name encodes the threshold mode, value, and sidedness, e.g. `runLevel_p-unc_p0.01_2s` or `datasetLevel_fdr_a0.05_2s`. If `ROI_MASK` is set, `_svc` is appended.

`manifest.tsv` records every stat map processed, the threshold applied, the threshold value, and the paths to all output figures. It is the authoritative record of what was plotted and how.

The 3D HTML viewers (`.html`) can be opened with VSCode Live Server over SSH without a Jupyter tunnel.

---

## PDF Reports And Analysis Indexes

`run_pipeline.sh` and `submit_pipeline.sh` now support a `report` step, which calls `scripts/report/generate_model_report.py` to build user-facing PDF summaries under `reports/<task_group>/`.

Typical examples:

```bash
$SLB_ANALYSIS_ROOT/scripts/run/run_pipeline.sh \
  --config "$SLB_USER_CONFIGS/tmth/tmth_visual_vs_baseline.cfg" \
  --steps plot-run,plot-group,report

$SLB_ANALYSIS_ROOT/scripts/run/submit_pipeline.sh \
  --config "$SLB_USER_CONFIGS/tmth/tmth_visual_vs_baseline.cfg" \
  --steps plot-run,plot-group,report
```

Analysis indexes are generated separately with `scripts/report/build_analysis_index.py`. For each task group, the script writes:

- `docs/indexes/<task_group>_analysis_index.md`
- `docs/indexes/<task_group>_analysis_index.json`

The Markdown index is human-readable and contains a summary table with the GLM, contrasts, and report path per model. The JSON file is the machine-readable companion payload.

The documentation folder is organized as:

```
docs/
  dictionaries/   CSV data dictionaries used by event-building scripts
  indexes/        Per-task-group analysis indexes (.md + .json)
```
