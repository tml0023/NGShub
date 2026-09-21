import { useEffect, useState } from 'react'
import { api } from '../api'
import type { Catalog, Reference, SampleRow } from '../api'

const FASTQ_EXTENSION = /\.(fastq|fq)(\.gz)?$/i
const READ_SUFFIX = /^(.+?)[._](?:R)?([12])(?:_\d+)?$/i

export function deriveSamples(files: File[]): SampleRow[] {
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
  const [references, setReferences] = useState<Reference[]>([])
  const [name, setName] = useState('')
  const [files, setFiles] = useState<File[]>([])
  const [samples, setSamples] = useState<SampleRow[]>([])
  const [reference, setReference] = useState('')
  const [referenceFile, setReferenceFile] = useState<File | null>(null)
  const [choices, setChoices] = useState<Record<string, string>>({})
  const [callers, setCallers] = useState<string[]>([])
  const [skipFastqc, setSkipFastqc] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => {
    api.catalog().then((data) => {
      setCatalog(data)
      setChoices(Object.fromEntries(data.steps.map((step) => [step.id, step.default])))
      setCallers(data.callers.default)
    }).catch((err) => setError(err.message))
    api.references().then(setReferences).catch(() => setReferences([]))
  }, [])

  function onFilesChosen(chosen: FileList | null) {
    const list = chosen ? [...chosen] : []
    setFiles(list)
    setSamples(deriveSamples(list))
  }

  function toggleCaller(value: string) {
    setCallers((current) =>
      current.includes(value) ? current.filter((c) => c !== value) : [...current, value],
    )
  }

  function updateSample(index: number, sample: string) {
    setSamples((current) =>
      current.map((row, i) => (i === index ? { ...row, sample } : row)),
    )
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault()
    setError(null)

    if (samples.length === 0) return setError('Upload at least one FASTQ file')
    if (!reference && !referenceFile) return setError('Choose or upload a reference genome')
    if (callers.length === 0) return setError('Select at least one variant caller')

    const body = new FormData()
    body.append('name', name || `run-${new Date().toISOString().slice(0, 16)}`)
    body.append(
      'config',
      JSON.stringify({ ...choices, callers, skip_fastqc: skipFastqc, reference }),
    )
    body.append('samples', JSON.stringify(samples))
    for (const file of files) body.append('files', file)
    if (referenceFile) body.append('reference_file', referenceFile)

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

  if (!catalog) return <p className="muted">Loading pipeline options…</p>

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
      </section>

      <section className="card">
        <h2>Input data</h2>
        <p className="muted">
          {catalog.platform.label} — {catalog.platform.description}
        </p>

        <label className="field">
          <span>FASTQ files</span>
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
                <th>Read 2</th>
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
                  <td className="mono">{row.fastq_2 ?? <span className="muted">single-end</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

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
      </section>

      {catalog.steps.map((step) => (
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
                <span className="option-label">{option.label}</span>
                <span className="option-description">{option.description}</span>
              </label>
            ))}
          </div>
        </section>
      ))}

      <section className="card">
        <h2>{catalog.callers.label}</h2>
        <p className="muted">Select one or more callers — each produces its own VCF.</p>
        <div className="options">
          {catalog.callers.options.map((option) => (
            <label
              key={option.value}
              className={`option ${callers.includes(option.value) ? 'selected' : ''}`}
            >
              <input
                type="checkbox"
                checked={callers.includes(option.value)}
                onChange={() => toggleCaller(option.value)}
              />
              <span className="option-label">{option.label}</span>
              <span className="option-description">{option.description}</span>
            </label>
          ))}
        </div>
      </section>

      <section className="card">
        <label className="checkbox">
          <input
            type="checkbox"
            checked={skipFastqc}
            onChange={(e) => setSkipFastqc(e.target.checked)}
          />
          <span>Skip FastQC (MultiQC still runs)</span>
        </label>
      </section>

      {error && <p className="error">{error}</p>}

      <button className="primary" type="submit" disabled={submitting}>
        {submitting ? 'Starting…' : 'Start run'}
      </button>
    </form>
  )
}
