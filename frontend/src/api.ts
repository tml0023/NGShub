export interface Option {
  value: string
  label: string
  description: string
  requires_docker?: boolean
}

export interface Step {
  id: string
  label: string
  default: string
  options: Option[]
}

export interface Platform {
  id: string
  label: string
  description: string
  paired: boolean
  steps: Step[]
  callers: { id: string; label: string; multiple: boolean; default: string[]; options: Option[] }
  sv_callers: { id: string; label: string; multiple: boolean; default: string[]; options: Option[] }
  flags: { id: string; label: string; default: boolean; description: string; requires_known_sites?: boolean }[]
  needs_annotation?: boolean
  needs_condition?: boolean
  needs_primers?: boolean
  always_requires_docker?: boolean
}

export interface Catalog {
  platforms: Record<string, Platform>
}

export interface Reference {
  name: string
  size: number
}

export interface SetupStatus {
  docker: { available: boolean; detail: string | null }
  references: Record<string, boolean>
  known_sites: Record<string, boolean>
  annotations: Record<string, boolean>
}

export interface SampleRow {
  sample: string
  fastq_1: string
  fastq_2: string | null
  condition?: string | null
}

export interface Task {
  name: string
  process: string
  status: string
  duration: string
  exit: string
}

export interface Run {
  id: string
  name: string
  status: 'queued' | 'running' | 'succeeded' | 'failed' | 'cancelled'
  platform: string
  params: Record<string, string | boolean>
  samples: SampleRow[]
  created_at: string
  started_at: string | null
  finished_at: string | null
  exit_code: number | null
  error: string | null
  tasks?: Task[]
}

export interface ResultFile {
  path: string
  size: number
}

export interface Variant {
  chrom: string
  pos: number
  ref: string
  alt: string
  qual: string
  filter: string
}

export interface VariantPage {
  caller: string
  file: string
  sample: string
  samples: string[]
  total: number
  variants: Variant[]
}

async function parse<T>(response: Response): Promise<T> {
  if (!response.ok) {
    const body = await response.json().catch(() => null)
    throw new Error(body?.detail ?? `${response.status} ${response.statusText}`)
  }
  return response.json() as Promise<T>
}

export const api = {
  catalog: () => fetch('/api/catalog').then(parse<Catalog>),
  references: () => fetch('/api/references').then(parse<Reference[]>),
  setupStatus: () => fetch('/api/setup-status').then(parse<SetupStatus>),
  runs: () => fetch('/api/runs').then(parse<Run[]>),
  run: (id: string) => fetch(`/api/runs/${id}`).then(parse<Run>),
  createRun: (body: FormData) =>
    fetch('/api/runs', { method: 'POST', body }).then(parse<{ id: string }>),
  cancel: (id: string) =>
    fetch(`/api/runs/${id}/cancel`, { method: 'POST' }).then(parse<{ status: string }>),
  log: (id: string, offset: number) =>
    fetch(`/api/runs/${id}/log?offset=${offset}`).then(parse<{ offset: number; text: string }>),
  files: (id: string) => fetch(`/api/runs/${id}/files`).then(parse<ResultFile[]>),
  variants: (id: string, caller: string, sample?: string) =>
    fetch(
      `/api/runs/${id}/variants?caller=${caller}${sample ? `&sample=${encodeURIComponent(sample)}` : ''}`,
    ).then(parse<VariantPage>),
  downloadUrl: (id: string, path: string) =>
    `/api/runs/${id}/download?path=${encodeURIComponent(path)}`,
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  const units = ['KB', 'MB', 'GB', 'TB']
  let value = bytes / 1024
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  return `${value.toFixed(1)} ${units[unit]}`
}
