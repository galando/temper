/**
 * Type definitions for OpenCode plugin API
 *
 * These types are based on the OpenCode plugin documentation.
 * When @opencode-ai/plugin is available, these can be replaced with the actual package.
 */

export interface PluginContext {
  project: unknown
  directory: string
  worktree: string
  client: unknown
  $: unknown
}

export interface ToolContext {
  directory: string
  worktree: string
}

// Schema type builders with proper chaining
export interface StringSchema {
  describe: (desc: string) => StringSchema
  optional: () => OptionalStringSchema
}

export interface OptionalStringSchema {
  default: (val: string) => StringSchema
  describe: (desc: string) => StringSchema
}

export interface EnumSchema<T extends string = string> {
  optional: () => OptionalEnumSchema<T>
  describe: (desc: string) => EnumSchema<T>
}

export interface OptionalEnumSchema<T extends string = string> {
  default: (val: T) => EnumSchema<T>
  describe: (desc: string) => EnumSchema<T>
}

export interface NumberSchema {
  min: (min: number) => MinNumberSchema
  describe: (desc: string) => NumberSchema
}

export interface MinNumberSchema {
  max: (max: number) => MaxNumberSchema
}

export interface MaxNumberSchema {
  optional: () => OptionalNumberSchema
}

export interface OptionalNumberSchema {
  default: (val: number) => NumberSchema
  describe: (desc: string) => NumberSchema
}

export interface ArraySchema {
  optional: () => OptionalArraySchema
  describe: (desc: string) => ArraySchema
}

export interface OptionalArraySchema {
  describe: (desc: string) => ArraySchema
}

export interface BooleanSchema {
  optional: () => OptionalBooleanSchema
  describe: (desc: string) => BooleanSchema
}

export interface OptionalBooleanSchema {
  default: (val: boolean) => BooleanSchema
  describe: (desc: string) => BooleanSchema
}

export interface ToolArgsSchema {
  string: () => StringSchema
  enum: <T extends readonly string[]>(values: [...T]) => EnumSchema<T[number]>
  number: () => NumberSchema
  array: <T>(schema: T) => ArraySchema
  boolean: () => BooleanSchema
}

export interface ToolDefinition<TArgs = Record<string, unknown>> {
  description: string
  args: Record<string, unknown>
  execute: (args: TArgs, context: ToolContext) => Promise<ToolResult>
}

export interface ToolResult {
  instructions: string
}

export interface PluginHooks {
  tool?: Record<string, ToolDefinition<Record<string, unknown>>>
}

export type Plugin = (ctx: PluginContext) => Promise<PluginHooks>

// Schema implementation
const stringSchema: StringSchema = {
  describe: function(this: StringSchema, _desc: string): StringSchema { return this },
  optional: function(): OptionalStringSchema {
    return {
      default: (_val: string) => stringSchema,
      describe: (_desc: string) => stringSchema
    }
  }
}

const createEnumSchema = <T extends string>(): EnumSchema<T> => ({
  optional: function(): OptionalEnumSchema<T> {
    return {
      default: (_val: T) => createEnumSchema<T>(),
      describe: (_desc: string) => createEnumSchema<T>()
    }
  },
  describe: function(this: EnumSchema<T>, _desc: string): EnumSchema<T> { return this }
})

const numberSchema: NumberSchema = {
  min: function(_min: number): MinNumberSchema {
    return {
      max: function(_max: number): MaxNumberSchema {
        return {
          optional: function(): OptionalNumberSchema {
            return {
              default: (_val: number) => numberSchema,
              describe: (_desc: string) => numberSchema
            }
          }
        }
      }
    }
  },
  describe: function(this: NumberSchema, _desc: string): NumberSchema { return this }
}

const arraySchema: ArraySchema = {
  optional: function(): OptionalArraySchema {
    return {
      describe: (_desc: string) => arraySchema
    }
  },
  describe: function(this: ArraySchema, _desc: string): ArraySchema { return this }
}

const booleanSchema: BooleanSchema = {
  optional: function(): OptionalBooleanSchema {
    return {
      default: (_val: boolean) => booleanSchema,
      describe: (_desc: string) => booleanSchema
    }
  },
  describe: function(this: BooleanSchema, _desc: string): BooleanSchema { return this }
}

/**
 * Schema helpers for defining tool arguments
 */
export const schema: ToolArgsSchema = {
  string: () => stringSchema,
  enum: <T extends readonly string[]>(_values: [...T]): EnumSchema<T[number]> => createEnumSchema<T[number]>(),
  number: () => numberSchema,
  array: <T>(_schema: T): ArraySchema => arraySchema,
  boolean: () => booleanSchema
}

/**
 * Tool helper function
 * Creates a tool definition with proper typing
 */
export function tool<TArgs extends Record<string, unknown>>(
  definition: ToolDefinition<TArgs>
): ToolDefinition<Record<string, unknown>> {
  return definition as ToolDefinition<Record<string, unknown>>
}

// Assign schema to tool
tool.schema = schema
