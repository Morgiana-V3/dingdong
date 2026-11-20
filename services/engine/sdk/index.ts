import type { DingdongPluginModule, SourceDefinition } from './dingdong-plugin.d.ts';

export type * from './dingdong-plugin.d.ts';
export { AuthExpiredError } from '../src/credentials.ts';
export { renderHtmlTemplate } from '../src/template-engine.ts';
export { loadImage } from '../src/images.ts';

/**
 * Helper for authoring Dingdong plugins with full TypeScript IntelliSense.
 * Zero runtime overhead: simply returns the plugin definition as-is.
 */
export function definePlugin(plugin: DingdongPluginModule): DingdongPluginModule {
  return plugin;
}

/**
 * Helper for strongly typing a single source registration.
 */
export function defineSource<
  TConfig = Record<string, unknown>,
  TState = Record<string, unknown>,
>(definition: SourceDefinition<TConfig, TState>): SourceDefinition<TConfig, TState> {
  return definition;
}
