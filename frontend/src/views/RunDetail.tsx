import { useCallback, useEffect, useRef, useState } from 'react'
import { api, formatBytes } from '../api'
import type { ResultFile, Run, VariantPage } from '../api'
import { StatusBadge } from './RunList'

const ACTIVE = new Set(['queued', 'running'])

function ProgressTable({ run }: { run: Run }) {
  const tasks = run.tasks ?? []
  if (tasks.length === 0) {
    return <p className="muted">No task activity reported yet.</p>
  }
  return (
    <table className="table">
      <thead>
        <tr>
          <th>Process</th>
          <th>Task</th>
          <th>Status</th>
          <th>Duration</th>
        </tr>
      </thead>
      <tbody>
        {tasks.map((task) => (
          <tr key={task.name}>
            <td className="mono small">{task.process}</td>
            <td className="small">{task.name}</td>
            <td>
              <span className={`badge badge-task-${task.status.toLowerCase()}`}>
                {task.status}
              </span>
            </td>
            <td className="small">{task.duration}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

function LogPanel({ runId, active }: { runId: string; active: boolean }) {
  const [text, setText] = useState('')
  const offset = useRef(0)
  const box = useRef<HTMLPreElement>(null)

  const poll = useCallback(async () => {
    const chunk = await api.log(runId, offset.current)
    if (chunk.text) {
      offset.current = chunk.offset
      setText((current) => current + chunk.text)
    }
  }, [runId])

  useEffect(() => {
    offset.current = 0
    setText('')
    poll().catch(() => undefined)
    if (!active) return
    const timer = setInterval(() => poll().catch(() => undefined), 2000)
    return () => clearInterval(timer)
  }, [poll, active])

  useEffect(() => {
    if (box.current) box.current.scrollTop = box.current.scrollHeight
  }, [text])

  return <pre className="log" ref={box}>{text || 'Waiting for output…'}</pre>
}

function FileBrowser({ runId }: { runId: string }) {
  const [files, setFiles] = useState<ResultFile[] | null>(null)

  useEffect(() => {
    api.files(runId).then(setFiles).catch(() => setFiles([]))
  }, [runId])

  if (!files) return <p className="muted">Loading files…</p>
  if (files.length === 0) return <p className="muted">No result files yet.</p>

  return (
    <table className="table">
      <thead>
        <tr>
          <th>File</th>
          <th>Size</th>
          <th />
        </tr>
      </thead>
      <tbody>
        {files.map((file) => (
          <tr key={file.path}>
            <td className="mono small">{file.path}</td>
            <td className="small">{formatBytes(file.size)}</td>
            <td>
              <a href={api.downloadUrl(runId, file.path)}>download</a>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

function VariantBrowser({
  runId,
  callers,
  samples,
}: {
  runId: string
  callers: string[]
  samples: string[]
}) {
  const [caller, setCaller] = useState(callers[0] ?? '')
  const [sample, setSample] = useState(samples.length === 1 ? samples[0] : '')
  const [page, setPage] = useState<VariantPage | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!caller) return
    if (samples.length > 1 && !sample) return
    setPage(null)
    setError(null)
    api
      .variants(runId, caller, sample || undefined)
      .then(setPage)
      .catch((err) => setError(err.message))
  }, [runId, caller, sample, samples.length])

  return (
    <div className="stack">
      <div className="row">
        {callers.map((name) => (
          <button
            key={name}
            className={`chip ${caller === name ? 'chip-active' : ''}`}
            onClick={() => setCaller(name)}
            type="button"
          >
            {name}
          </button>
        ))}
      </div>

      {samples.length > 1 && (
        <div className="row">
          {samples.map((name) => (
            <button
              key={name}
              className={`chip ${sample === name ? 'chip-active' : ''}`}
              onClick={() => setSample(name)}
              type="button"
            >
              {name}
            </button>
          ))}
        </div>
      )}

      {samples.length > 1 && !sample && (
        <p className="muted small">Select a sample to view its variants.</p>
      )}

      {error && <p className="muted">{error}</p>}
      {page && (
        <>
          <p className="muted small">
            {page.total.toLocaleString()} variants in {page.file}
            {page.total > page.variants.length &&
              ` — showing first ${page.variants.length}`}
          </p>
          <table className="table">
            <thead>
              <tr>
                <th>CHROM</th>
                <th>POS</th>
                <th>REF</th>
                <th>ALT</th>
                <th>QUAL</th>
                <th>FILTER</th>
              </tr>
            </thead>
            <tbody>
              {page.variants.map((variant) => (
                <tr key={`${variant.chrom}:${variant.pos}:${variant.alt}`}>
                  <td className="mono small">{variant.chrom}</td>
                  <td className="mono small">{variant.pos.toLocaleString()}</td>
                  <td className="mono small">{variant.ref}</td>
                  <td className="mono small">{variant.alt}</td>
                  <td className="small">{variant.qual}</td>
                  <td className="small">{variant.filter}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </div>
  )
}

export function RunDetail({ runId, onBack }: { runId: string; onBack: () => void }) {
  const [run, setRun] = useState<Run | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [tab, setTab] = useState<'progress' | 'log' | 'files' | 'variants'>('progress')

  const settled = run !== null && !ACTIVE.has(run.status)

  useEffect(() => {
    let live = true
    const load = () =>
      api
        .run(runId)
        .then((data) => live && setRun(data))
        .catch((err) => live && setError(err.message))
    load()
    if (settled) return () => { live = false }
    const timer = setInterval(load, 2500)
    return () => {
      live = false
      clearInterval(timer)
    }
  }, [runId, settled])

  if (error) return <p className="error">{error}</p>
  if (!run) return <p className="muted">Loading run…</p>

  const active = ACTIVE.has(run.status)
  const callers = String(run.params.callers ?? '').split(',').filter(Boolean)
  const sampleNames = run.samples.map((s) => s.sample)

  return (
    <div className="stack">
      <div className="row space-between">
        <div>
          <button className="link" onClick={onBack} type="button">
            ← All runs
          </button>
          <h2 className="tight">
            {run.name} <StatusBadge status={run.status} />
          </h2>
          <p className="mono muted small">{run.id}</p>
        </div>
        {active && (
          <button
            className="danger"
            type="button"
            onClick={() => api.cancel(run.id).catch(() => undefined)}
          >
            Cancel run
          </button>
        )}
      </div>

      <section className="card">
        <div className="chips">
          <span className="chip">platform: {run.platform}</span>
          {run.params.trimmer != null && (
            <span className="chip">trimming: {String(run.params.trimmer)}</span>
          )}
          {run.params.aligner != null && (
            <span className="chip">aligner: {String(run.params.aligner)}</span>
          )}
          {run.params.markduplicates != null && (
            <span className="chip">markdup: {String(run.params.markduplicates)}</span>
          )}
          <span className="chip">callers: {String(run.params.callers)}</span>
          <span className="chip">{run.samples.length} sample(s)</span>
        </div>
        {run.error && <pre className="log error-log">{run.error}</pre>}
      </section>

      <div className="tabs">
        {(['progress', 'log', 'files', 'variants'] as const).map((key) => (
          <button
            key={key}
            type="button"
            className={`tab ${tab === key ? 'tab-active' : ''}`}
            onClick={() => setTab(key)}
          >
            {key}
          </button>
        ))}
      </div>

      {tab === 'progress' && <ProgressTable run={run} />}
      {tab === 'log' && <LogPanel runId={run.id} active={active} />}
      {tab === 'files' && <FileBrowser runId={run.id} />}
      {tab === 'variants' && (
        <VariantBrowser runId={run.id} callers={callers} samples={sampleNames} />
      )}
    </div>
  )
}
