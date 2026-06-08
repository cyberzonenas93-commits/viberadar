import { defineInt, defineSecret, defineString } from "firebase-functions/params";

export const SPOTIFY_CLIENT_ID = defineSecret("SPOTIFY_CLIENT_ID");
export const SPOTIFY_CLIENT_SECRET = defineSecret("SPOTIFY_CLIENT_SECRET");
export const YOUTUBE_API_KEY = defineSecret("YOUTUBE_API_KEY");
export const APPLE_MUSIC_DEVELOPER_TOKEN = defineSecret("APPLE_MUSIC_DEVELOPER_TOKEN");
export const SOUNDCLOUD_CLIENT_ID = defineSecret("SOUNDCLOUD_CLIENT_ID");
export const SOUNDCLOUD_OAUTH_TOKEN = defineSecret("SOUNDCLOUD_OAUTH_TOKEN");
export const BEATPORT_API_TOKEN = defineSecret("BEATPORT_API_TOKEN");
export const AUDIOMACK_CONSUMER_KEY = defineSecret("AUDIOMACK_CONSUMER_KEY");
export const AUDIOMACK_CONSUMER_SECRET = defineSecret("AUDIOMACK_CONSUMER_SECRET");
export const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
export const SOUNDCHARTS_APP_ID = defineSecret("SOUNDCHARTS_APP_ID");
export const SOUNDCHARTS_API_KEY = defineSecret("SOUNDCHARTS_API_KEY");
export const SOUNDCHARTS_DEFAULT_PLATFORMS =
  "shazam,tiktok,boomplay,soundcloud,beatport";
export const SOUNDCHARTS_PLATFORMS = defineString("SOUNDCHARTS_PLATFORMS", {
  default: SOUNDCHARTS_DEFAULT_PLATFORMS,
});
export const SOUNDCHARTS_BASE_URL = "https://customer.api.soundcharts.com";
export const BEATPORT_API_BASE_URL = defineString("BEATPORT_API_BASE_URL", {
  default: "",
});
export const INGEST_REGIONS = defineString("INGEST_REGIONS", {
  default: "US,GB,GH,NG,ZA,DE",
});
export const USAGE_FREE_AI_MONTHLY_LIMIT = defineInt(
  "USAGE_FREE_AI_MONTHLY_LIMIT",
  {
    default: 5,
  },
);
export const USAGE_FREE_PLATFORM_PROXY_MONTHLY_LIMIT = defineInt(
  "USAGE_FREE_PLATFORM_PROXY_MONTHLY_LIMIT",
  {
    default: 100,
  },
);
export const USAGE_FREE_MANUAL_INGEST_DAILY_LIMIT = defineInt(
  "USAGE_FREE_MANUAL_INGEST_DAILY_LIMIT",
  {
    default: 0,
  },
);
export const USAGE_PRO_AI_MONTHLY_LIMIT = defineInt("USAGE_PRO_AI_MONTHLY_LIMIT", {
  default: 100,
});
export const USAGE_PRO_PLATFORM_PROXY_MONTHLY_LIMIT = defineInt(
  "USAGE_PRO_PLATFORM_PROXY_MONTHLY_LIMIT",
  {
    default: 1500,
  },
);
export const USAGE_PRO_MANUAL_INGEST_DAILY_LIMIT = defineInt(
  "USAGE_PRO_MANUAL_INGEST_DAILY_LIMIT",
  {
    default: 1,
  },
);
export const USAGE_STUDIO_AI_MONTHLY_LIMIT = defineInt(
  "USAGE_STUDIO_AI_MONTHLY_LIMIT",
  {
    default: 400,
  },
);
export const USAGE_STUDIO_PLATFORM_PROXY_MONTHLY_LIMIT = defineInt(
  "USAGE_STUDIO_PLATFORM_PROXY_MONTHLY_LIMIT",
  {
    default: 7500,
  },
);
export const USAGE_STUDIO_MANUAL_INGEST_DAILY_LIMIT = defineInt(
  "USAGE_STUDIO_MANUAL_INGEST_DAILY_LIMIT",
  {
    default: 3,
  },
);

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

function safeValue(param: { value: () => string }): string | undefined {
  try {
    const v = param.value();
    return v === "" ? undefined : v;
  } catch {
    return undefined;
  }
}

/** Real Soundcharts credentials, or null when unset/placeholder (the no-op
 *  signal that keeps the client dormant in production until a key is set).
 *  Reads process.env first so unit tests work without the params runtime. */
export function getSoundchartsCreds(): { appId: string; apiKey: string } | null {
  const appId = normalizeSecretValue(
    process.env.SOUNDCHARTS_APP_ID ?? safeValue(SOUNDCHARTS_APP_ID),
  );
  const apiKey = normalizeSecretValue(
    process.env.SOUNDCHARTS_API_KEY ?? safeValue(SOUNDCHARTS_API_KEY),
  );
  if (!appId || !apiKey) return null;
  return { appId, apiKey };
}

export function getSoundchartsPlatforms(): string[] {
  const raw =
    process.env.SOUNDCHARTS_PLATFORMS ??
    safeValue(SOUNDCHARTS_PLATFORMS) ??
    SOUNDCHARTS_DEFAULT_PLATFORMS;
  return raw
    .split(",")
    .map((p) => p.trim().toLowerCase())
    .filter(Boolean);
}
