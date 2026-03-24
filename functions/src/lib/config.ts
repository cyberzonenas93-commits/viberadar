import { defineSecret, defineString } from "firebase-functions/params";

export const SPOTIFY_CLIENT_ID = defineSecret("SPOTIFY_CLIENT_ID");
export const SPOTIFY_CLIENT_SECRET = defineSecret("SPOTIFY_CLIENT_SECRET");
export const YOUTUBE_API_KEY = defineSecret("YOUTUBE_API_KEY");
export const APPLE_MUSIC_DEVELOPER_TOKEN = defineSecret("APPLE_MUSIC_DEVELOPER_TOKEN");
export const SOUNDCLOUD_CLIENT_ID = defineSecret("SOUNDCLOUD_CLIENT_ID");
export const SOUNDCLOUD_OAUTH_TOKEN = defineSecret("SOUNDCLOUD_OAUTH_TOKEN");
export const BEATPORT_API_TOKEN = defineSecret("BEATPORT_API_TOKEN");
export const BEATPORT_API_BASE_URL = defineString("BEATPORT_API_BASE_URL", {
  default: "",
});
export const INGEST_REGIONS = defineString("INGEST_REGIONS", {
  default: "US,GB,GH,NG,ZA,DE",
});

export function normalizeSecretValue(value?: string): string | undefined {
  const normalized = (value ?? "").trim();
  if (
    normalized === "" ||
    normalized === "UNCONFIGURED" ||
    normalized === "PENDING" ||
    normalized === "PLACEHOLDER"
  ) {
    return undefined;
  }

  return normalized;
}

export function getConfiguredRegions(): string[] {
  return INGEST_REGIONS.value()
    .split(",")
    .map((item) => item.trim().toUpperCase())
    .filter(Boolean);
}

export function appleStorefrontForRegion(region: string): string {
  const mapping: Record<string, string> = {
    US: "us",
    GB: "gb",
    GH: "gh",
    NG: "ng",
    ZA: "za",
    DE: "de",
    FR: "fr",
    CA: "ca",
    AU: "au",
  };
  return mapping[region] ?? "us";
}

export function getBeatportApiBaseUrl(): string | undefined {
  const value = BEATPORT_API_BASE_URL.value().trim();
  return value === "" ? undefined : value;
}
