// Where the Temper script is, for the texts that name it. Pure. The stage names are in stages.ts.

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
