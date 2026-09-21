"""Tool options exposed to the UI.

Values must match the choices validated in pipeline/main.nf.
"""

CATALOG = {
    "platform": {
        "id": "illumina",
        "label": "Illumina (short read)",
        "description": "Paired- or single-end short reads, germline SNV/indel calling",
    },
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
        ],
    },
    "flags": [
        {
            "id": "skip_fastqc",
            "label": "Skip FastQC",
            "default": False,
            "description": "Disable per-sample FastQC reports (MultiQC still runs)",
        }
    ],
}

VALID = {
    "trimmer": {o["value"] for o in CATALOG["steps"][0]["options"]},
    "aligner": {o["value"] for o in CATALOG["steps"][1]["options"]},
    "markduplicates": {o["value"] for o in CATALOG["steps"][2]["options"]},
    "callers": {o["value"] for o in CATALOG["callers"]["options"]},
}
