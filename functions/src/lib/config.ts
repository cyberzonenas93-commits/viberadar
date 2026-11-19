import {
  defineBoolean,
  defineInt,
  defineSecret,
  defineString,
} from "firebase-functions/params";

export const SPOTIFY_CLIENT_ID = defineSecret("SPOTIFY_CLIENT_ID");
export const SPOTIFY_CLIENT_SECRET = defineSecret("SPOTIFY_CLIENT_SECRET");
export const YOUTUBE_API_KEY = defineSecret("YOUTUBE_API_KEY");
export const APPLE_MUSIC_DEVELOPER_TOKEN = defineSecret(
  "APPLE_MUSIC_DEVELOPER_TOKEN",
);
// MusicKit signing inputs for on-demand developer-token generation. Preferred
// over the static APPLE_MUSIC_DEVELOPER_TOKEN (which expires and silently 500s
// once stale). See lib/appleMusicToken.ts.
export const APPLE_MUSIC_PRIVATE_KEY = defineSecret("APPLE_MUSIC_PRIVATE_KEY");
export const APPLE_MUSIC_KEY_ID = defineSecret("APPLE_MUSIC_KEY_ID");
export const APPLE_MUSIC_TEAM_ID = defineSecret("APPLE_MUSIC_TEAM_ID");
export const SOUNDCLOUD_CLIENT_ID = defineSecret("SOUNDCLOUD_CLIENT_ID");
export const SOUNDCLOUD_OAUTH_TOKEN = defineSecret("SOUNDCLOUD_OAUTH_TOKEN");
export const BEATPORT_API_TOKEN = defineSecret("BEATPORT_API_TOKEN");
export const AUDIOMACK_CONSUMER_KEY = defineSecret("AUDIOMACK_CONSUMER_KEY");
export const AUDIOMACK_CONSUMER_SECRET = defineSecret(
  "AUDIOMACK_CONSUMER_SECRET",
);
export const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
export const APP_STORE_ISSUER_ID = defineSecret("APP_STORE_ISSUER_ID");
export const APP_STORE_KEY_ID = defineSecret("APP_STORE_KEY_ID");
export const APP_STORE_PRIVATE_KEY = defineSecret("APP_STORE_PRIVATE_KEY");
export const APP_STORE_APP_APPLE_ID = defineInt("APP_STORE_APP_APPLE_ID", {
  default: 0,
  description:
    "Numeric App Apple ID required for production App Store signed-data verification.",
});
export const SOUNDCHARTS_APP_ID = defineSecret("SOUNDCHARTS_APP_ID");
export const SOUNDCHARTS_API_KEY = defineSecret("SOUNDCHARTS_API_KEY");
export const SOUNDCHARTS_DEFAULT_PLATFORMS = "shazam,tiktok,boomplay";
export const SOUNDCHARTS_PLATFORMS = defineString("SOUNDCHARTS_PLATFORMS", {
  default: SOUNDCHARTS_DEFAULT_PLATFORMS,
});
export const REQUIRE_APP_CHECK = defineBoolean("REQUIRE_APP_CHECK", {
  default: false,
  description:
    "When true, client-facing callable/HTTP functions require Firebase App Check tokens.",
});
export const CONSUME_APP_CHECK_TOKEN = defineBoolean(
  "CONSUME_APP_CHECK_TOKEN",
  {
    default: false,
    description:
      "When true, callable functions consume limited-use App Check tokens for replay protection.",
  },
);
export const SOUNDCHARTS_BASE_URL = "https://customer.api.soundcharts.com";
export const BEATPORT_API_BASE_URL = defineString("BEATPORT_API_BASE_URL", {
  default: "",
});
export const INGEST_REGIONS = defineString("INGEST_REGIONS", {
  default: "US,GB,GH,NG,ZA,DE",
});
export const OPENAI_DEFAULT_MODEL = defineString("OPENAI_DEFAULT_MODEL", {
  default: "gpt-5.5",
});
export const OPENAI_ALLOWED_MODELS = defineString("OPENAI_ALLOWED_MODELS", {
  default: "gpt-5.5,gpt-4.1,gpt-4o-mini",
});
export const OPENAI_MAX_COMPLETION_TOKENS = defineInt(
  "OPENAI_MAX_COMPLETION_TOKENS",
  {
    default: 4000,
  },
);
export const OPENAI_MAX_MESSAGES = defineInt("OPENAI_MAX_MESSAGES", {
  default: 24,
});
export const OPENAI_MAX_MESSAGE_CHARS = defineInt("OPENAI_MAX_MESSAGE_CHARS", {
  default: 12000,
});
export const PAIRING_CREATE_DAILY_LIMIT = defineInt(
  "PAIRING_CREATE_DAILY_LIMIT",
  {
    default: 25,
  },
);
export const PAIRING_CLAIM_DAILY_LIMIT = defineInt(
  "PAIRING_CLAIM_DAILY_LIMIT",
  {
    default: 40,
  },
);
export const APP_STORE_BUNDLE_ID = defineString("APP_STORE_BUNDLE_ID", {
  default: "com.viberadar.viberadar",
});
export const APP_STORE_ENVIRONMENT = defineString("APP_STORE_ENVIRONMENT", {
  default: "Production",
});
export const APP_STORE_PRODUCT_IDS = defineString("APP_STORE_PRODUCT_IDS", {
  default: "viberadar_pro_monthly,viberadar_pro_yearly",
});
export const USAGE_FREE_AI_MONTHLY_LIMIT = defineInt(
  "USAGE_FREE_AI_MONTHLY_LIMIT",
  {
    default: 0,
  },
);
export const USAGE_FREE_PLATFORM_PROXY_MONTHLY_LIMIT = defineInt(
  "USAGE_FREE_PLATFORM_PROXY_MONTHLY_LIMIT",
  {
    default: 0,
  },
);
export const USAGE_FREE_MANUAL_INGEST_DAILY_LIMIT = defineInt(
  "USAGE_FREE_MANUAL_INGEST_DAILY_LIMIT",
  {
    default: 0,
  },
);
export const USAGE_PRO_AI_MONTHLY_LIMIT = defineInt(
  "USAGE_PRO_AI_MONTHLY_LIMIT",
  {
    default: 100,
  },
);
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

export function splitCsvParam(raw: string): string[] {
  return raw
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

export function getAllowedOpenAiModels(): string[] {
  return splitCsvParam(OPENAI_ALLOWED_MODELS.value());
}

export function getAppStoreProductIds(): string[] {
  return splitCsvParam(APP_STORE_PRODUCT_IDS.value());
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

export function safeParamValue(param: {
  value: () => string;
}): string | undefined {
  return safeValue(param);
}

/** Real Soundcharts credentials, or null when unset/placeholder (the no-op
 *  signal that keeps the client dormant in production until a key is set).
 *  Reads process.env first so unit tests work without the params runtime. */
export function getSoundchartsCreds(): {
  appId: string;
  apiKey: string;
} | null {
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
