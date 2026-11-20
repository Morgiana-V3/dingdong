export interface XPost {
  id: string;
  authorName: string;
  authorHandle: string;
  repostedBy?: string;
  text: string;
  url: string;
  publishedAt: string;
  images: string[];
  hasVideo: boolean;
  quote?: {
    authorName: string;
    authorHandle: string;
    text: string;
  };
  likes: number;
  reposts: number;
  replies: number;
}

export interface XConfig {
  handles: string[];
  query: string;
  includeReposts: boolean;
  limit: number;
  filterModel: string;
  filterPrompt: string;
  summaryModel: string;
}

export interface XTemplateData {
  taskName: string;
  generatedAt: string;
  subtitle: string;
  aiSummary?: string;
  filteredOutCount?: number;
  items: XPost[];
}
