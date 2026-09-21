import { useEffect, useState } from 'react'
import { api } from '../api'
import type { Run } from '../api'

export function StatusBadge({ status }: { status: Run['status'] }) {
  return <span className={`badge badge-${status}`}>{status}</span>
}

export function RunList({ onOpen }: { onOpen: (id: string) => void }) {
  const [runs, setRuns] = useState<Run[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    const load = () =>
      api
        .runs()
        .then((data) => active && setRuns(data))
        .catch((err) => active && setError(err.message))
    load()
    const timer = setInterval(load, 4000)
    return () => {
      active = false
      clearInterval(timer)
    }
  }, [])

  if (error) return <p className="error">{error}</p>
  if (!runs) return <p className="muted">Loading runs…</p>
  if (runs.length === 0) return <p className="muted">No runs yet. Start one from “New run”.</p>

  return (
    <table className="table">
      <thead>
        <tr>
          <th>Run</th>
          <th>Status</th>
          <th>Samples</th>
          <th>Aligner</th>
          <th>Callers</th>
          <th>Created</th>
        </tr>
      </thead>
      <tbody>
        {runs.map((run) => (
          <tr key={run.id} className="clickable" onClick={() => onOpen(run.id)}>
            <td>
              <strong>{run.name}</strong>
              <div className="mono muted small">{run.id}</div>
            </td>
            <td>
              <StatusBadge status={run.status} />
            </td>
            <td>{run.samples.length}</td>
            <td>{String(run.params.aligner ?? '')}</td>
            <td>{String(run.params.callers ?? '')}</td>
            <td className="small">{new Date(run.created_at).toLocaleString()}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
