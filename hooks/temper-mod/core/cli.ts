// Where the Temper script is, for the texts that name it. Pure. The stage names are those of STAGE_SEQ_TEMPER in
// scripts/temper (a test there keeps the two in step).

export const CLI = 'scripts/temper'

// Where the mod's module file sits in the plugin folder: the plugin folder is its module URL with this taken off.
export const MOD_FILE = '/hooks/temper-mod/register.tsx'

// The Temper script in the plugin folder as a full path, from the module URL of the mod (<plugin> followed by
// MOD_FILE). The path is decoded FIRST and then checked, so an encoded space or quote (%20, %27) cannot reach a
// command. Any odd location gives `scripts/temper`.
export function pluginCliFrom(url: string | undefined): string {
  try {
    const here = decodeURIComponent(new URL(url ?? '').pathname)
    if (here.endsWith(MOD_FILE) && !/[\s'"`$;&|<>()\\]/.test(here)) return `${here.slice(0, -MOD_FILE.length)}/scripts/temper`
  } catch {
    // no module URL here
  }
  return CLI
}

// The plugin folder, from where the Temper script is (what pluginCliFrom gave). Null when only the plain
// `scripts/temper` is known.
export function pluginRootOf(cli: string): string | null {
  const tail = '/scripts/temper'
  return cli !== CLI && cli.startsWith('/') && cli.endsWith(tail) ? cli.slice(0, -tail.length) : null
}

// STAGE_SEQ_TEMPER, in order.
export const CLI_STAGES = 'intent plan design build review check'

const STAGES = CLI_STAGES.split(' ')

export const isCliStage = (s: string): boolean => STAGES.includes(s)
