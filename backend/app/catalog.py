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
        "sv_callers": {
            "id": "sv_callers",
            "label": "Structural variant calling (optional)",
            "multiple": True,
            "default": [],
            "options": [
                {
                    "value": "manta",
                    "label": "Manta",
                    "description": "Illumina's own SV caller; fast, widely used, integrates well with short-read BAMs. "
                                    "No native macOS build; runs in a container.",
                    "requires_docker": True,
                },
                {
                    "value": "delly",
                    "label": "Delly",
                    "description": "Read-pair/split-read SV caller; a well-regarded second option to cross-check Manta calls",
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
        "sv_callers": {
            "id": "sv_callers",
            "label": "Structural variant calling (optional)",
            "multiple": True,
            "default": [],
            "options": [
                {
                    "value": "pbsv",
                    "label": "pbsv",
                    "description": "PacBio's own SV caller, built and tuned specifically for HiFi/CCS reads",
                },
                {
                    "value": "sniffles2",
                    "label": "Sniffles2",
                    "description": "Widely used long-read SV caller, platform-agnostic; a good second option to cross-check pbsv",
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
        "sv_callers": {
            "id": "sv_callers",
            "label": "Structural variant calling (optional)",
            "multiple": True,
            "default": [],
            "options": [
                {
                    "value": "sniffles2",
                    "label": "Sniffles2",
                    "description": "Widely used long-read SV caller, platform-agnostic; the most established option for ONT",
                },
                {
                    "value": "cutesv",
                    "label": "cuteSV",
                    "description": "Long-read SV caller with an ONT-tuned preset; a good second option to cross-check Sniffles2",
                },
            ],
        },
        "flags": [],
    },
    "illumina_rna": {
        "id": "illumina_rna",
        "label": "Illumina (RNA-seq)",
        "description": "Paired- or single-end short-read RNA-seq — gene/transcript quantification, "
                        "plus differential expression when samples are assigned to 2+ conditions",
        "paired": True,
        "pipeline": "rna/illumina/main.nf",
        "needs_annotation": True,
        "needs_condition": True,
        "steps": [
            {
                "id": "trimmer",
                "label": "QC & trimming",
                "default": "trimgalore",
                "options": [
                    {
                        "value": "trimgalore",
                        "label": "Trim Galore",
                        "description": "Adapter/quality trimming; nf-core/rnaseq's default trimmer",
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
                "default": "star",
                "options": [
                    {
                        "value": "star",
                        "label": "STAR",
                        "description": "Splice-aware aligner; the field standard for short-read RNA-seq, "
                                        "used by nf-core/rnaseq",
                    },
                ],
            },
        ],
        "callers": {
            "id": "callers",
            "label": "Quantification",
            "multiple": True,
            "default": ["salmon"],
            "options": [
                {
                    "value": "salmon",
                    "label": "Salmon",
                    "description": "Transcript- and gene-level quantification; nf-core/rnaseq's default quantifier. "
                                    "Feeds DESeq2 via tximport when 2+ sample conditions are present.",
                },
            ],
        },
        "sv_callers": {
            "id": "sv_callers",
            "label": "",
            "multiple": True,
            "default": [],
            "options": [],
        },
        "flags": [
            {
                "id": "skip_fastqc",
                "label": "Skip FastQC",
                "default": False,
                "description": "Disable per-sample FastQC reports (MultiQC still runs)",
            },
        ],
    },
    "pacbio_rna": {
        "id": "pacbio_rna",
        "label": "PacBio Iso-Seq (long read)",
        "description": "Single-end full-length cDNA — isoform discovery and classification against a "
                        "reference annotation (gene/transcript counts, not differential expression)",
        "paired": False,
        "pipeline": "rna/pacbio/main.nf",
        "needs_annotation": True,
        "needs_condition": False,
        "needs_primers": True,
        "always_requires_docker": True,
        "steps": [],
        "callers": {
            "id": "callers",
            "label": "Isoform classification",
            "multiple": True,
            "default": ["pigeon"],
            "options": [
                {
                    "value": "pigeon",
                    "label": "pigeon",
                    "description": "PacBio's official isoform classifier (built on SQANTI3); classifies "
                                    "collapsed transcripts against a reference annotation as known/novel "
                                    "genes/isoforms.",
                },
            ],
        },
        "sv_callers": {
            "id": "sv_callers",
            "label": "",
            "multiple": True,
            "default": [],
            "options": [],
        },
        "flags": [],
    },
    "ont_rna": {
        "id": "ont_rna",
        "label": "Oxford Nanopore (RNA-seq)",
        "description": "Single-end long-read cDNA/direct RNA — transcript reconstruction and "
                        "quantification, including novel isoforms (not differential expression)",
        "paired": False,
        "pipeline": "rna/ont/main.nf",
        "needs_annotation": True,
        "needs_condition": False,
        "steps": [
            {
                "id": "trimmer",
                "label": "QC & filtering",
                "default": "chopper",
                "options": [
                    {
                        "value": "chopper",
                        "label": "chopper",
                        "description": "Quality (Q≥10) and length (≥500bp) filtering before alignment",
                    },
                    {
                        "value": "none",
                        "label": "No filtering",
                        "description": "Align raw reads as supplied",
                    },
                ],
            },
            {
                "id": "aligner",
                "label": "Alignment",
                "default": "minimap2",
                "options": [
                    {
                        "value": "minimap2",
                        "label": "minimap2 (spliced)",
                        "description": "Splice-aware long-read alignment (-x splice); the field standard "
                                        "for ONT RNA-seq, used by nf-core/nanoseq",
                    },
                ],
            },
        ],
        "callers": {
            "id": "callers",
            "label": "Transcript quantification",
            "multiple": True,
            "default": ["bambu"],
            "options": [
                {
                    "value": "bambu",
                    "label": "Bambu",
                    "description": "Reconstructs and quantifies transcripts (including novel isoforms) in "
                                    "one step; nf-core/nanoseq's primary recommended quantifier",
                },
                {
                    "value": "stringtie2",
                    "label": "StringTie2 + featureCounts",
                    "description": "Alternative transcript assembly path offered by nf-core/nanoseq",
                },
            ],
        },
        "sv_callers": {
            "id": "sv_callers",
            "label": "",
            "multiple": True,
            "default": [],
            "options": [],
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
        "sv_callers": {o["value"] for o in platform["sv_callers"]["options"]},
    }
    for platform_id, platform in PLATFORMS.items()
}


def needs_docker(platform_id: str, params: dict) -> bool:
    """True if any tool selected in `params` runs in a container.

    `params` is the run's stored Nextflow params: one value per step id, plus
    a comma-joined `callers` string.
    """
    platform = PLATFORMS[platform_id]
    if platform.get("always_requires_docker"):
        return True
    for step in platform["steps"]:
        chosen = params.get(step["id"])
        if any(o["value"] == chosen and o.get("requires_docker") for o in step["options"]):
            return True
    chosen_callers = str(params.get("callers", "")).split(",")
    if any(
        o["value"] in chosen_callers and o.get("requires_docker")
        for o in platform["callers"]["options"]
    ):
        return True
    chosen_sv_callers = str(params.get("sv_callers", "")).split(",")
    return any(
        o["value"] in chosen_sv_callers and o.get("requires_docker")
        for o in platform["sv_callers"]["options"]
    )
