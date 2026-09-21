import { useEffect, useState } from 'react'
import { NewRun } from './views/NewRun'
import { RunList } from './views/RunList'
import { RunDetail } from './views/RunDetail'

type Route = { view: 'new' } | { view: 'runs' } | { view: 'run'; id: string }

function parseHash(): Route {
  const hash = window.location.hash.replace(/^#\/?/, '')
  if (hash.startsWith('runs/')) return { view: 'run', id: hash.slice(5) }
  if (hash === 'runs') return { view: 'runs' }
  return { view: 'new' }
}

export default function App() {
  const [route, setRoute] = useState<Route>(parseHash)

  useEffect(() => {
    const onChange = () => setRoute(parseHash())
    window.addEventListener('hashchange', onChange)
    return () => window.removeEventListener('hashchange', onChange)
  }, [])

  const go = (path: string) => {
    window.location.hash = path
  }

  return (
    <div className="app">
      <header className="header">
        <div className="brand">
          <span className="logo">ngs-web</span>
          <span className="muted small">Illumina FASTQ → VCF</span>
        </div>
        <nav>
          <button
            className={`nav ${route.view === 'new' ? 'nav-active' : ''}`}
            onClick={() => go('/new')}
            type="button"
          >
            New run
          </button>
          <button
            className={`nav ${route.view !== 'new' ? 'nav-active' : ''}`}
            onClick={() => go('/runs')}
            type="button"
          >
            Runs
          </button>
        </nav>
      </header>

      <main className="main">
        {route.view === 'new' && <NewRun onCreated={(id) => go(`/runs/${id}`)} />}
        {route.view === 'runs' && <RunList onOpen={(id) => go(`/runs/${id}`)} />}
        {route.view === 'run' && (
          <RunDetail runId={route.id} onBack={() => go('/runs')} />
        )}
      </main>
    </div>
  )
}
