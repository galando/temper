// The mod's type check enters here (tsconfig.mod.json includes this folder, not the mod's own):
// the hooks module imports every file of the mod, so tsc checks them all through this import.
// Not a test file and never loaded by the plugin.
export { register } from '../../hooks/temper-mod/register'
