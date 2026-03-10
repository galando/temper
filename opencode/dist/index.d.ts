/**
 * Type definitions for OpenCode plugin API
 *
 * These types are based on the OpenCode plugin documentation.
 * When @opencode-ai/plugin is available, these can be replaced with the actual package.
 */
interface PluginContext {
    project: unknown;
    directory: string;
    worktree: string;
    client: unknown;
    $: unknown;
}
interface ToolContext {
    directory: string;
    worktree: string;
}
interface ToolDefinition<TArgs = Record<string, unknown>> {
    description: string;
    args: Record<string, unknown>;
    execute: (args: TArgs, context: ToolContext) => Promise<ToolResult>;
}
interface ToolResult {
    instructions: string;
}
interface PluginHooks {
    tool?: Record<string, ToolDefinition<Record<string, unknown>>>;
}
type Plugin = (ctx: PluginContext) => Promise<PluginHooks>;

/**
 * Temper Plugin for OpenCode
 *
 * Quality gates, blast radius analysis, and adaptive learning for AI-generated code.
 *
 * Commands available:
 * - temper_plan: Plan feature with blast radius analysis
 * - temper_build: Execute plan with TDD and quality gates
 * - temper_review: Code review with confidence scoring
 * - temper_check: Stack-aware validation pipeline
 * - temper_fix: Root cause analysis + structured bug fix
 * - temper_standards: Build team engineering standards
 * - temper_status: Quality metrics dashboard
 */
declare const TemperPlugin: Plugin;

export { TemperPlugin, TemperPlugin as default };
