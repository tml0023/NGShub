"""Tool options exposed to the UI, per sequencing platform.

Values must match the choices validated in each platform's main.nf.
"""

PLATFORMS = {
    "illumina": {
        "id": "illumina",
        "label": "Illumina (short read)",
        "description": "Paired- or single-end short reads, germline SNV/indel calling",
        "paired": True,
        "pipeline": "main.nf",
        "steps": [
            {
                "id": "trimmer",
                "label": "QC & trimming",
                "default": "fastp",
                "options": [
                    {
                        "value": "fastp",
                        "label": "fastp",
                        "description": "Fast adapter/quality trimming with built-in QC reporting",
                    },
                    {
                        "value": "trimgalore",
                        "label": "Trim Galore",
                        "description": "Cutadapt wrapper; conservative adapter removal",
                    },
                    {
                        "value": "none",
                        "label": "No trimming",
                        "description": "Align raw reads as supplied",
                    },
                ],
            },
            {
                "id": "aligner",
                "label": "Alignment",
                "default": "bwamem2",
                "options": [
                    {
                        "value": "bwamem2",
                        "label": "BWA-MEM2",
                        "description": "Faster successor to BWA-MEM; same alignment output",
                    },
                    {
                        "value": "bwa",
                        "label": "BWA-MEM",
                        "description": "Long-standing reference aligner; lower memory footprint",
                    },
                    {
                        "value": "bowtie2",
                        "label": "Bowtie2",
                        "description": "End-to-end or local alignment; widely used for short reads",
                    },
                    {
                        "value": "dragmap",
                        "label": "DragMap",
                        "description": "Illumina's open-source aligner, developed alongside DRAGEN. No native macOS build; runs in a container.",
                        "requires_docker": True,
                    },
                ],
            },
            {
                "id": "markduplicates",
                "label": "Pre-processing",
                "default": "gatk",
                "options": [
                    {
                        "value": "gatk",
                        "label": "GATK MarkDuplicates",
                        "description": "Picard-based duplicate marking; GATK best-practice default",
                    },
                    {
                        "value": "samtools",
                        "label": "samtools markdup",
                        "description": "Lighter and faster; needs fixmate name-sort round trip",
                    },
                    {
                        "value": "none",
                        "label": "Skip duplicate marking",
                        "description": "Appropriate for amplicon or targeted panels",
                    },
                ],
            },
        ],
        "callers": {
            "id": "callers",
            "label": "Variant calling",
            "multiple": True,
            "default": ["haplotypecaller"],
            "options": [
                {
                    "value": "haplotypecaller",
                    "label": "GATK HaplotypeCaller",
                    "description": "Local de novo assembly; GATK best-practice germline caller",
                },
                {
                    "value": "bcftools",
                    "label": "bcftools call",
                    "description": "Fast pileup-based calling; good baseline for high-depth data",
                },
                {
                    "value": "freebayes",
                    "label": "FreeBayes",
                    "description": "Haplotype-based Bayesian caller; handles pooled samples",
                },
                {
                    "value": "deepvariant",
                    "label": "DeepVariant",
                    "description": "Google's deep-learning caller; highly accurate. Runs in a container (no lightweight native install).",
                    "requires_docker": True,
                },
            ],
        },
        "flags": [
            {
                "id": "skip_fastqc",
                "label": "Skip FastQC",
                "default": False,
                "description": "Disable per-sample FastQC reports (MultiQC still runs)",
            },
            {
                "id": "bqsr",
                "label": "Base quality score recalibration (BQSR)",
                "default": False,
                "description": "GATK BaseRecalibrator + ApplyBQSR, run after duplicate marking. "
                                "Needs known-variant sites matched to the reference genome — "
                                "only available for the built-in hg38.fa and hg19.fa right now.",
                "requires_known_sites": True,
            },
        ],
    },
    "pacbio": {
        "id": "pacbio",
        "label": "PacBio HiFi (long read)",
        "description": "Single-end long reads, germline SNV/indel calling",
        "paired": False,
        "pipeline": "pacbio/main.nf",
        "steps": [
            {
                "id": "markduplicates",
                "label": "Pre-processing",
                "default": "none",
                "options": [
                    {
                        "value": "none",
                        "label": "Skip duplicate marking",
                        "description": "HiFi library prep makes PCR duplication far less common than with short reads; "
                                        "this is the typical default",
                    },
                    {
                        "value": "pbmarkdup",
                        "label": "pbmarkdup",
                        "description": "PacBio's reference-free duplicate detector, run on raw reads before alignment. "
                                        "No native macOS build; runs in a container.",
                        "requires_docker": True,
                    },
                ],
            },
            {
                "id": "aligner",
                "label": "Alignment",
                "default": "pbmm2",
                "options": [
                    {
                        "value": "pbmm2",
                        "label": "pbmm2",
                        "description": "PacBio's official minimap2 wrapper with HiFi-tuned presets; the standard choice",
                    },
                    {
                        "value": "minimap2",
                        "label": "minimap2",
                        "description": "The aligner pbmm2 wraps, used directly with the map-hifi preset",
                    },
                ],
            },
        ],
        "callers": {
            "id": "callers",
            "label": "Variant calling",
            "multiple": True,
            "default": ["deepvariant"],
            "options": [
                {
                    "value": "deepvariant",
                    "label": "DeepVariant",
                    "description": "Most benchmarked, most recommended caller for HiFi germline calling (GIAB/PrecisionFDA). "
                                    "Runs in a container.",
                    "requires_docker": True,
                },
                {
                    "value": "clair3",
                    "label": "Clair3",
                    "description": "Well-regarded long-read caller, offered as a second option. Runs in a container.",
                    "requires_docker": True,
                },
            ],
        },
        "flags": [],
    },
    "ont": {
        "id": "ont",
        "label": "Oxford Nanopore (long read)",
        "description": "Single-end long reads, germline SNV/indel calling",
        "paired": False,
        "pipeline": "ont/main.nf",
        "steps": [
            {
                "id": "trimmer",
                "label": "QC & filtering",
                "default": "chopper",
                "options": [
                    {
                        "value": "chopper",
                        "label": "chopper",
                        "description": "Quality (Q≥10) and length (≥500bp) filtering. Raw ONT reads, unlike "
                                        "HiFi's already-consensus-accurate output, benefit from this before alignment.",
                    },
                    {
                        "value": "none",
                        "label": "No filtering",
                        "description": "Align raw reads as supplied",
                    },
                ],
            },
            {
                "id": "markduplicates",
                "label": "Pre-processing",
                "default": "none",
                "options": [
                    {
                        "value": "none",
                        "label": "Skip duplicate marking",
                        "description": "ONT libraries are typically PCR-free; this is the typical default",
                    },
                    {
                        "value": "samtools",
                        "label": "samtools markdup",
                        "description": "Post-alignment duplicate marking, if your library prep used PCR amplification",
                    },
                ],
            },
        ],
        "callers": {
            "id": "callers",
            "label": "Variant calling",
            "multiple": True,
            "default": ["clair3"],
            "options": [
                {
                    "value": "clair3",
                    "label": "Clair3",
                    "description": "The most benchmarked, most widely used caller for ONT germline calling; "
                                    "developed with ONT as a primary target platform. Runs in a container.",
                    "requires_docker": True,
                },
                {
                    "value": "deepvariant",
                    "label": "DeepVariant",
                    "description": "Google's deep-learning caller, with a model tuned for R10.4.1 ONT chemistry. "
                                    "Runs in a container.",
                    "requires_docker": True,
                },
            ],
        },
        "flags": [],
    },
}

VALID = {
    platform_id: {
        "trimmer": {o["value"] for step in platform["steps"] if step["id"] == "trimmer" for o in step["options"]},
        "aligner": {o["value"] for step in platform["steps"] if step["id"] == "aligner" for o in step["options"]},
        "markduplicates": {
            o["value"] for step in platform["steps"] if step["id"] == "markduplicates" for o in step["options"]
        },
        "callers": {o["value"] for o in platform["callers"]["options"]},
    }
    for platform_id, platform in PLATFORMS.items()
}


def needs_docker(platform_id: str, params: dict) -> bool:
    """True if any tool selected in `params` runs in a container.

    `params` is the run's stored Nextflow params: one value per step id, plus
    a comma-joined `callers` string.
    """
    platform = PLATFORMS[platform_id]
    for step in platform["steps"]:
        chosen = params.get(step["id"])
        if any(o["value"] == chosen and o.get("requires_docker") for o in step["options"]):
            return True
    chosen_callers = str(params.get("callers", "")).split(",")
    return any(
        o["value"] in chosen_callers and o.get("requires_docker")
        for o in platform["callers"]["options"]
    )
