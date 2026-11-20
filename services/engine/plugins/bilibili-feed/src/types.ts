export interface BilibiliFeedConfig {
  feedType: 'all' | 'video';
  keywords?: string;
  limit: number;
  aiProvider?: string;
}

export interface BilibiliFeedState {
  seenIds?: string[];
  initialized?: boolean;
}

export interface BilibiliNavResponse {
  code: number;
  message?: string;
  data?: {
    isLogin?: boolean;
    uname?: string;
    mid?: number;
    face?: string;
  };
}

export interface BilibiliDynamicItem {
  id_str?: string;
  type?: string;
  modules?: {
    module_author?: {
      name?: string;
      pub_ts?: number;
    };
    module_dynamic?: {
      desc?: { text?: string };
      major?: {
        archive?: {
          bvid?: string;
          title?: string;
          desc?: string;
          cover?: string;
          jump_url?: string;
        };
        opus?: {
          title?: string;
          summary?: { text?: string };
          jump_url?: string;
          pics?: Array<{ url?: string }>;
        };
        draw?: {
          items?: Array<{ src?: string }>;
        };
      };
    };
  };
}

export interface BilibiliFeedResponse {
  code: number;
  message?: string;
  data?: {
    items?: BilibiliDynamicItem[];
  };
}

export interface ParsedDynamic {
  id: string;
  title: string;
  body: string;
  source: string;
  url: string;
  images: string[];
  publishedAt?: number;
}
