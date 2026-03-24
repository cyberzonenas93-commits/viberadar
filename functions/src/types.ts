export interface SourceTrackSignal {
  source:
    | "spotify"
    | "youtube"
    | "apple"
    | "soundcloud"
    | "beatport"
    | "audius";
  sourceId: string;
  title: string;
  artist: string;
  artworkUrl?: string;
  genre?: string;
  bpm?: number;
  key?: string;
  keywords: string[];
  region?: string;
  platformUrl: string;
  engagement: number;
  growthRate: number;
  recency: number;
  releasedAt?: string;
}

export interface UnifiedTrackRecord {
  id: string;
  title: string;
  artist: string;
  artwork_url: string;
  bpm: number | null;
  key: string;
  genre: string;
  vibe: string;
  trend_score: number;
  region_scores: Record<string, number>;
  platform_links: Record<string, string>;
  created_at: string;
  updated_at: string;
  energy_level: number;
  trend_history: Array<{ label: string; score: number }>;
  source_count: number;
}

export interface IngestionSummary {
  fetchedSignals: number;
  writtenTracks: number;
  regions: string[];
  sources: string[];
}
