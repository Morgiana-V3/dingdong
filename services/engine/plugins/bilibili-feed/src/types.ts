export interface BilibiliFeedConfig {
  feedType: 'all' | 'video';
  upIds?: string[];
  keywords?: string;
  limit: number;
  filterModel?: string;
  filterPrompt?: string;
  summaryModel?: string;
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

export interface BilibiliFollowingsResponse {
  code: number;
  message?: string;
  data?: {
    list?: Array<{
      mid?: number;
      uname?: string;
      sign?: string;
    }>;
  };
}

export interface BilibiliRichTextNode {
  type?: string;
  text?: string;
  orig_text?: string;
  emoji?: {
    text?: string;
    icon_url?: string;
  };
}

export interface BilibiliDynamicItem {
  id_str?: string;
  type?: string;
  modules?: {
    module_author?: {
      mid?: number;
      name?: string;
      pub_ts?: number;
    };
    module_dynamic?: {
      desc?: {
        text?: string;
        rich_text_nodes?: BilibiliRichTextNode[];
      };
      major?: {
        archive?: {
          bvid?: string;
          title?: string;
          desc?: string;
          cover?: string;
          duration_text?: string;
          jump_url?: string;
        };
        opus?: {
          title?: string;
          summary?: {
            text?: string;
            rich_text_nodes?: BilibiliRichTextNode[];
          };
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

export interface RichSegment {
  type: 'text' | 'emoji';
  text: string;
  url?: string;
}

export interface ParsedDynamic {
  id: string;
  authorMid: string;
  title: string;
  bodyText: string;
  bodySegments: RichSegment[];
  source: string;
  url: string;
  isVideo: boolean;
  duration?: string;
  images: string[];
  publishedAt?: number;
}
