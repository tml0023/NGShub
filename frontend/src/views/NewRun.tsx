import { useEffect, useState } from 'react'
import { api } from '../api'
import type { Catalog, Platform, Reference, SampleRow, SetupStatus } from '../api'

const FASTQ_EXTENSION = /\.(fastq|fq)(\.gz)?$/i
const READ_SUFFIX = /^(.+?)[._](?:R)?([12])(?:_\d+)?$/i

export function deriveSamples(files: File[], paired: boolean): SampleRow[] {
  if (!paired) {
    // Long-read platforms (e.g. PacBio HiFi): single-end, one file per sample.
    return files.map((file) => ({
      sample: file.name.replace(FASTQ_EXTENSION, ''),
      fastq_1: file.name,
      fastq_2: null,
    }))
  }

  const groups = new Map<string, { fastq_1?: string; fastq_2?: string }>()

  for (const file of files) {
    const base = file.name.replace(FASTQ_EXTENSION, '')
    const match = base.match(READ_SUFFIX)
    const sample = match ? match[1] : base
    const entry = groups.get(sample) ?? {}
    if (match && match[2] === '2') {
      entry.fastq_2 = file.name
    } else {
      entry.fastq_1 = file.name
    }
    groups.set(sample, entry)
  }

  return [...groups.entries()]
    .filter(([, reads]) => reads.fastq_1)
    .map(([sample, reads]) => ({
      sample,
      fastq_1: reads.fastq_1 as string,
      fastq_2: reads.fastq_2 ?? null,
    }))
}

export function NewRun({ onCreated }: { onCreated: (id: string) => void }) {
  const [catalog, setCatalog] = useState<Catalog | null>(null)
  const [platformId, setPlatformId] = useState<string>('')
  const [references, setReferences] = useState<Reference[]>([])
  const [setupStatus, setSetupStatus] = useState<SetupStatus | null>(null)
  const [name, setName] = useState('')
  const [files, setFiles] = useState<File[]>([])
  const [samples, setSamples] = useState<SampleRow[]>([])
  const [reference, setReference] = useState('')
  const [referenceFile, setReferenceFile] = useState<File | null>(null)
  const [annotationFile, setAnnotationFile] = useState<File | null>(null)
  const [primersFile, setPrimersFile] = useState<File | null>(null)
  const [choices, setChoices] = useState<Record<string, string>>({})
  const [callers, setCallers] = useState<string[]>([])
  const [svCallers, setSvCallers] = useState<string[]>([])
  const [flags, setFlags] = useState<Record<string, boolean>>({})
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  function applyDefaults(id: string, platforms: Record<string, Platform>) {
    const next = platforms[id]
    if (!next) return
    setPlatformId(id)
    setChoices(Object.fromEntries(next.steps.map((step) => [step.id, step.default])))
    setCallers(next.callers.default)
    setSvCallers(next.sv_callers.default)
    setFlags(Object.fromEntries(next.flags.map((flag) => [flag.id, flag.default])))
    setFiles([])
    setSamples([])
    setAnnotationFile(null)
    setPrimersFile(null)
  }

  useEffect(() => {
    api.catalog().then((data) => {
      setCatalog(data)
      applyDefaults(Object.keys(data.platforms)[0], data.platforms)
    }).catch((err) => setError(err.message))
    api.references().then(setReferences).catch(() => setReferences([]))
    api.setupStatus().then(setSetupStatus).catch(() => setSetupStatus(null))
  }, [])

  const platform: Platform | null = catalog && platformId ? catalog.platforms[platformId] : null

  function selectPlatform(id: string) {
    if (catalog) applyDefaults(id, catalog.platforms)
  }

  // Selected tools that need Docker, so we can warn before submitting rather
  // than let the run fail minutes later on a container pull.
  const dockerToolsSelected: string[] = platform
    ? [
        ...(platform.always_requires_docker ? [platform.label] : []),
        ...platform.steps.flatMap((step) =>
          step.options.filter((o) => o.value === choices[step.id] && o.requires_docker).map((o) => o.label),
        ),
        ...platform.callers.options.filter((o) => callers.includes(o.value) && o.requires_docker).map((o) => o.label),
        ...platform.sv_callers.options
          .filter((o) => svCallers.includes(o.value) && o.requires_docker)
          .map((o) => o.label),
      ]
    : []
  const dockerUnavailable =
    dockerToolsSelected.length > 0 && setupStatus?.docker.available === false

  const bqsrOn = Boolean(flags.bqsr)
  const bqsrKnownSitesReady = reference ? setupStatus?.known_sites[reference] : undefined
  const bqsrBlocked = bqsrOn && !referenceFile && reference !== '' && bqsrKnownSitesReady === false

  const needsAnnotation = Boolean(platform?.needs_annotation)
  const annotationReady = reference ? setupStatus?.annotations[reference] : undefined
  const annotationBlocked =
    needsAnnotation && !referenceFile && !annotationFile && reference !== '' && annotationReady === false

  function onFilesChosen(chosen: FileList | null) {
    const list = chosen ? [...chosen] : []
    setFiles(list)
    setSamples(deriveSamples(list, platform?.paired ?? true))
  }

  function toggleCaller(value: string) {
    setCallers((current) =>
      current.includes(value) ? current.filter((c) => c !== value) : [...current, value],
    )
  }

  function toggleSvCaller(value: string) {
    setSvCallers((current) =>
      current.includes(value) ? current.filter((c) => c !== value) : [...current, value],
    )
  }

  function updateSample(index: number, sample: string) {
    setSamples((current) =>
      current.map((row, i) => (i === index ? { ...row, sample } : row)),
    )
  }

  function updateCondition(index: number, condition: string) {
    setSamples((current) =>
      current.map((row, i) => (i === index ? { ...row, condition: condition || null } : row)),
    )
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault()
    setError(null)

    if (!platform) return
    if (samples.length === 0) return setError('Upload at least one FASTQ file')
    const needsReference = platform.needs_reference !== false
    if (needsReference && !reference && !referenceFile) return setError('Choose or upload a reference genome')
    if (callers.length === 0) return setError('Select at least one variant caller')
    if (needsAnnotation && !referenceFile && !annotationFile && annotationReady === false) {
      return setError('This reference has no matching annotation (GTF) — upload one, or pick a different reference')
    }
    if (needsAnnotation && referenceFile && !annotationFile) {
      return setError('A custom reference needs a matching annotation (GTF) uploaded alongside it')
    }

    const body = new FormData()
    body.append('name', name || `run-${new Date().toISOString().slice(0, 16)}`)
    body.append(
      'config',
      JSON.stringify({ platform: platform.id, ...choices, callers, sv_callers: svCallers, ...flags, reference }),
    )
    body.append('samples', JSON.stringify(samples))
    for (const file of files) body.append('files', file)
    if (referenceFile) body.append('reference_file', referenceFile)
    if (annotationFile) body.append('annotation_file', annotationFile)
    if (primersFile) body.append('primers_file', primersFile)

    setSubmitting(true)
    try {
      const created = await api.createRun(body)
      onCreated(created.id)
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setSubmitting(false)
    }
  }

  if (!catalog || !platform) return <p className="muted">Loading pipeline options…</p>

  return (
    <form className="stack" onSubmit={submit}>
      <section className="card">
        <h2>Run details</h2>
        <label className="field">
          <span>Run name</span>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. trio-exome-batch3"
          />
        </label>

        <label className="field">
          <span>Sequencing platform</span>
          <select value={platformId} onChange={(e) => selectPlatform(e.target.value)}>
            {Object.values(catalog.platforms).map((p) => (
              <option key={p.id} value={p.id}>
                {p.label}
              </option>
            ))}
          </select>
        </label>
      </section>

      <section className="card">
        <h2>Input data</h2>
        <p className="muted">
          {platform.label} — {platform.description}
        </p>

        <label className="field">
          <span>{platform.paired ? 'FASTQ files' : 'FASTQ files (one per sample)'}</span>
          <input
            type="file"
            multiple
            accept=".fastq,.fq,.fastq.gz,.fq.gz"
            onChange={(e) => onFilesChosen(e.target.files)}
          />
        </label>

        {samples.length > 0 && (
          <table className="table">
            <thead>
              <tr>
                <th>Sample</th>
                <th>Read 1</th>
                {platform.paired && <th>Read 2</th>}
                {platform.needs_condition && <th>Condition</th>}
              </tr>
            </thead>
            <tbody>
              {samples.map((row, index) => (
                <tr key={row.fastq_1}>
                  <td>
                    <input
                      className="inline-input"
                      value={row.sample}
                      onChange={(e) => updateSample(index, e.target.value)}
                    />
                  </td>
                  <td className="mono">{row.fastq_1}</td>
                  {platform.paired && (
                    <td className="mono">
                      {row.fastq_2 ?? <span className="muted">single-end</span>}
                    </td>
                  )}
                  {platform.needs_condition && (
                    <td>
                      <input
                        className="inline-input"
                        placeholder="e.g. treated"
                        value={row.condition ?? ''}
                        onChange={(e) => updateCondition(index, e.target.value)}
                      />
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {platform.needs_condition && (
          <p className="muted small">
            Optional — assign samples to conditions (e.g. treated/control) to run differential
            expression. Leave blank to skip it and just get per-sample quantification.
          </p>
        )}

        {platform.needs_reference !== false && (
          <>
            <label className="field">
              <span>Reference genome</span>
              <select
                value={reference}
                onChange={(e) => setReference(e.target.value)}
                disabled={referenceFile !== null}
              >
                <option value="">Select a reference…</option>
                {references.map((ref) => (
                  <option key={ref.name} value={ref.name}>
                    {ref.name}
                  </option>
                ))}
              </select>
            </label>

            <label className="field">
              <span>…or upload a FASTA</span>
              <input
                type="file"
                accept=".fa,.fasta,.fna"
                onChange={(e) => setReferenceFile(e.target.files?.[0] ?? null)}
              />
            </label>
          </>
        )}

        {needsAnnotation && (
          <label className="field">
            <span>
              Gene annotation (GTF){referenceFile ? '' : ' — only needed if the selected reference has none bundled'}
            </span>
            <input
              type="file"
              accept=".gtf,.gff,.gff3"
              onChange={(e) => setAnnotationFile(e.target.files?.[0] ?? null)}
            />
            {annotationBlocked && (
              <p className="warning small flag-description">
                No bundled annotation for {reference}. Run <code>./scripts/setup_references.sh</code>,
                or upload a GTF above.
              </p>
            )}
          </label>
        )}

        {platform.needs_primers && (
          <label className="field">
            <span>…or upload your own Iso-Seq primers FASTA (optional)</span>
            <input
              type="file"
              accept=".fa,.fasta,.fna"
              onChange={(e) => setPrimersFile(e.target.files?.[0] ?? null)}
            />
            <p className="muted small">
              Defaults to the standard NEB Iso-Seq primers if left blank. Upload your own if your
              library prep used a different kit (e.g. Kinnex barcoded primers).
            </p>
          </label>
        )}
      </section>

      {platform.steps.map((step) => (
        <section className="card" key={step.id}>
          <h2>{step.label}</h2>
          <div className="options">
            {step.options.map((option) => (
              <label
                key={option.value}
                className={`option ${choices[step.id] === option.value ? 'selected' : ''}`}
              >
                <input
                  type="radio"
                  name={step.id}
                  value={option.value}
                  checked={choices[step.id] === option.value}
                  onChange={() => setChoices({ ...choices, [step.id]: option.value })}
                />
                <span className="option-label">
                  {option.label}
                  {option.requires_docker && <span className="badge-docker">docker</span>}
                </span>
                <span className="option-description">{option.description}</span>
              </label>
            ))}
          </div>
        </section>
      ))}

      <section className="card">
        <h2>{platform.callers.label}</h2>
        <p className="muted">Select one or more — each runs independently and publishes its own output.</p>
        <div className="options">
          {platform.callers.options.map((option) => (
            <label
              key={option.value}
              className={`option ${callers.includes(option.value) ? 'selected' : ''}`}
            >
              <input
                type="checkbox"
                checked={callers.includes(option.value)}
                onChange={() => toggleCaller(option.value)}
              />
              <span className="option-label">
                {option.label}
                {option.requires_docker && <span className="badge-docker">docker</span>}
              </span>
              <span className="option-description">{option.description}</span>
            </label>
          ))}
        </div>
      </section>

      {platform.sv_callers.options.length > 0 && (
      <section className="card">
        <h2>{platform.sv_callers.label}</h2>
        <p className="muted">
          Optional — detects larger rearrangements (deletions, insertions, duplications) that
          SNV/indel callers miss. Output VCFs use breakend notation and are only browsable via
          the Files tab.
        </p>
        <div className="options">
          {platform.sv_callers.options.map((option) => (
            <label
              key={option.value}
              className={`option ${svCallers.includes(option.value) ? 'selected' : ''}`}
            >
              <input
                type="checkbox"
                checked={svCallers.includes(option.value)}
                onChange={() => toggleSvCaller(option.value)}
              />
              <span className="option-label">
                {option.label}
                {option.requires_docker && <span className="badge-docker">docker</span>}
              </span>
              <span className="option-description">{option.description}</span>
            </label>
          ))}
        </div>
      </section>
      )}

      {platform.flags.length > 0 && (
        <section className="card">
          <div className="stack">
            {platform.flags.map((flag) => (
              <div key={flag.id}>
                <label className="checkbox">
                  <input
                    type="checkbox"
                    checked={flags[flag.id] ?? flag.default}
                    onChange={(e) => setFlags({ ...flags, [flag.id]: e.target.checked })}
                  />
                  <span>
                    {flag.label}
                    {flag.requires_known_sites && (
                      <span className="badge-docker">hg38 / hg19 only</span>
                    )}
                  </span>
                </label>
                <p className="muted small flag-description">{flag.description}</p>
                {flag.id === 'bqsr' && bqsrBlocked && (
                  <p className="warning small flag-description">
                    No known-sites resources found for {reference}. Run{' '}
                    <code>./scripts/setup_references.sh</code> to download them, or turn off BQSR.
                  </p>
                )}
              </div>
            ))}
          </div>
        </section>
      )}

      {dockerUnavailable && (
        <p className="warning">
          {dockerToolsSelected.join(', ')} {dockerToolsSelected.length === 1 ? 'needs' : 'need'} Docker.{' '}
          {setupStatus?.docker.detail ?? 'Docker is not available.'} Or pick a different option above.
        </p>
      )}

      {error && <p className="error">{error}</p>}

      <button className="primary" type="submit" disabled={submitting}>
        {submitting ? 'Starting…' : 'Start run'}
      </button>
    </form>
  )
}
