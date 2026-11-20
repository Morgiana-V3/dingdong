export interface TiebaThread {
  id: string;
  forum: string;
  title: string;
  author: string;
  excerpt: string;
  url: string;
  replyCount: number;
  isPinned: boolean;
  isGood: boolean;
  publishedAt: string;
  images: string[];
}

export interface TiebaConfig {
  forums: string[];
  sort: 'latest_reply' | 'latest_post' | 'good';
  includePinned: boolean;
  limit: number;
  filterModel: string;
  filterPrompt: string;
  summaryModel: string;
}

export interface TiebaTemplateData {
  taskName: string;
  generatedAt: string;
  forums: string[];
  aiSummary?: string;
  filteredOutCount?: number;
  items: TiebaThread[];
}
