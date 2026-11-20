export type FieldType =
  | 'text'
  | 'textarea'
  | 'number'
  | 'boolean'
  | 'select'
  | 'stringList'
  | 'secret'
  | 'aiProvider'
  | 'tasks';

export interface SelectOption {
  value: string;
  label: string;
  description?: string;
}

export interface PluginField {
  key: string;
  label: string;
  type: FieldType;
  required?: boolean;
  default?: unknown;
  placeholder?: string;
  help?: string;
  maxLength?: number;
  min?: number;
  max?: number;
  integer?: boolean;
  maxItems?: number;
  minItems?: number;
  options?: SelectOption[];
}

export interface WebCookieAuth {
  id: string;
  name: string;
  type: 'web-cookie';
  loginUrl: string;
  cookieDomains: string[];
  requiredCookies: string[];
  verify?: (
    credential: { cookie: string; cookies: Record<string, string> },
    ctx: { http: HttpService },
  ) => Promise<{ name?: string; id?: string; avatar?: string } | string | void>;
}

export interface TokenAuth {
  id: string;
  name: string;
  type: 'token';
  help?: string;
  placeholder?: string;
  verify?: (
    credential: { token: string },
    ctx: { http: HttpService },
  ) => Promise<{ name?: string; id?: string } | string | void>;
}

export type PluginAuth = WebCookieAuth | TokenAuth;

export interface Article {
  title: string;
  body?: string;
  source?: string;
  url?: string;
  images?: Array<string | { url: string; caption?: string }>;
  publishedAt?: number | string;
}

export interface ArticleMessage {
  title: string;
  short?: string;
  source?: string;
  articles: Article[];
}

export interface RawMessage {
  title: string;
  short?: string;
  source?: string;
  format: 'html' | 'markdown' | 'text';
  content: string;
}

export type PluginMessage = ArticleMessage | RawMessage;

export interface RunResult {
  message: PluginMessage | null;
  state?: Record<string, unknown>;
  detail?: string;
}

export interface HttpRequestOptions extends RequestInit {
  timeout?: number;
  proxy?: boolean;
}

export interface HttpService {
  fetch(url: string, options?: HttpRequestOptions): Promise<Response>;
  text(url: string, options?: HttpRequestOptions): Promise<string>;
  json<T = unknown>(url: string, options?: HttpRequestOptions): Promise<T>;
}

export interface TaskAIService {
  generate(
    input:
      | string
      | {
          system?: string;
          prompt?: string;
          messages?: Array<{ role: string; content: string }>;
          temperature?: number;
          maxTokens?: number;
          model?: string;
          timeout?: number;
        },
    signal?: AbortSignal,
  ): Promise<string>;
  json<T = unknown>(
    input:
      | string
      | {
          system?: string;
          prompt?: string;
          temperature?: number;
          maxTokens?: number;
          model?: string;
          timeout?: number;
        },
    signal?: AbortSignal,
  ): Promise<T>;
}

export type CredentialValue =
  | { cookie: string; cookies: Record<string, string> }
  | { token: string };

export interface JobContext<TConfig = Record<string, unknown>, TState = Record<string, unknown>> {
  taskId: string;
  taskName: string;
  config: TConfig;
  state: TState;
  credential: CredentialValue | null;
  ai: TaskAIService | null;
  getAI(providerId?: string): TaskAIService | null;
  http: HttpService;
  signal: AbortSignal;
  log(step: string, detail: string, status?: 'info' | 'warn' | 'error'): void;
}

export interface SourceDefinition<
  TConfig = Record<string, unknown>,
  TState = Record<string, unknown>,
> {
  id: string;
  name: string;
  description?: string;
  version?: string;
  builtin?: boolean;
  capabilities?: Array<'ai.required' | 'ai.optional'>;
  fields: PluginField[];
  auth?: PluginAuth;
  run?(job: JobContext<TConfig, TState>): Promise<RunResult>;
}

export interface DingdongContext {
  source: {
    register<TConfig = Record<string, unknown>, TState = Record<string, unknown>>(
      definition: SourceDefinition<TConfig, TState>,
    ): () => void;
  };
  http: HttpService;
}

export interface DingdongPluginModule {
  name: string;
  inject?: { required?: string[]; optional?: string[] };
  apply(ctx: DingdongContext): void | Promise<void>;
}
