#!/usr/bin/env python3
"""Build a plain-language HTML surveillance summary from the GenoFLU
genotype call and the risk-marker JSON report. Screening result, not a
diagnosis -- see the explicit disclaimer rendered into every report."""
import csv
import html
import json
import sys


def read_genotype(path):
    with open(path) as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    return rows[0] if rows else {}


def main():
    sample, genotype_path, risk_path, out_path = sys.argv[1:5]

    genotype = read_genotype(genotype_path)
    with open(risk_path) as fh:
        risk = json.load(fh)

    genotype_call = genotype.get("Genotype", "unassigned")
    risk_level = risk["risk_level"]
    risk_colors = {"low": "#2e7d4f", "moderate": "#96701e", "high": "#a8402a", "unknown": "#5c6b6a"}
    risk_color = risk_colors.get(risk_level, "#5c6b6a")

    flagged_rows = "".join(
        f"<tr><td>{html.escape(m['gene'])}</td><td>{html.escape(m['name'])}</td>"
        f"<td>{html.escape(m['observed_aa'])}</td><td>{html.escape(m['status'])}</td>"
        f"<td>{html.escape(m['significance'])}</td><td>{html.escape(m['citation'])}</td></tr>"
        for m in risk["markers"]
    )

    genes_checked_rows = "".join(
        f"<tr><td>{html.escape(g)}</td><td>{html.escape(s)}</td></tr>"
        for g, s in risk["genes_checked"].items()
    )

    html_out = f"""<!doctype html>
<html><head><meta charset="utf-8"><title>Surveillance report: {html.escape(sample)}</title>
<style>
body {{ font-family: -apple-system, sans-serif; max-width: 860px; margin: 40px auto; padding: 0 20px; color: #1c2a2a; }}
h1 {{ font-size: 26px; }} h2 {{ font-size: 18px; margin-top: 36px; border-bottom: 1px solid #ddd; padding-bottom: 6px; }}
table {{ border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 14px; }}
th, td {{ text-align: left; padding: 8px 10px; border-bottom: 1px solid #eee; }}
th {{ background: #f4f3ec; font-size: 12px; text-transform: uppercase; color: #5c6b6a; }}
.badge {{ display: inline-block; padding: 4px 14px; border-radius: 99px; color: white; font-weight: 600; background: {risk_color}; }}
.disclaimer {{ background: #fbeae5; border-left: 3px solid #a8402a; padding: 14px 18px; margin: 20px 0; font-size: 14px; }}
</style></head>
<body>
<h1>Surveillance report</h1>
<p><strong>Sample:</strong> {html.escape(sample)}</p>

<div class="disclaimer">
<strong>Screening result, not a diagnosis.</strong> This report is a research-use
screening tool. A positive or high-risk result should be confirmed through an
approved diagnostic laboratory before any reporting or response action.
</div>

<h2>Summary</h2>
<table>
<tr><th>Genotype</th><td>{html.escape(genotype_call)}</td></tr>
<tr><th>Spillover risk</th><td><span class="badge">{html.escape(risk_level)}</span>
  &nbsp; {risk['flagged_markers']}/{risk['total_markers']} markers flagged</td></tr>
</table>

<h2>Risk markers checked</h2>
<table>
<thead><tr><th>Gene</th><th>Marker</th><th>Observed</th><th>Status</th><th>Significance</th><th>Citation</th></tr></thead>
<tbody>{flagged_rows}</tbody>
</table>

<h2>Technical appendix</h2>
<p><strong>Genes checked for risk markers:</strong></p>
<table>
<thead><tr><th>Gene</th><th>Status</th></tr></thead>
<tbody>{genes_checked_rows}</tbody>
</table>
<p><strong>Genotype detail:</strong> {html.escape(genotype.get("Genotype List Used, >=98.0%", "-"))}</p>
</body></html>
"""
    with open(out_path, "w") as fh:
        fh.write(html_out)


if __name__ == "__main__":
    main()
