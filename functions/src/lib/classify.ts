export function classifyVibe(input: {
  bpm?: number | null;
  genre?: string;
  keywords?: string[];
}): string {
  const genre = (input.genre ?? "").toLowerCase();
  const keywords = (input.keywords ?? []).map((item) => item.toLowerCase());
  const keywordText = ` ${keywords.join(" ")} `;
  const bpm = input.bpm ?? 120;

  if (/\b(drill|rage|hardcore)\b/.test(keywordText) || bpm >= 145) {
    return "aggressive";
  }
  if (genre.includes("amapiano") || genre === "afrobeats") {
    return bpm >= 120 ? "club" : "afro-smooth";
  }
  if (genre.includes("r&b") || genre.includes("soul")) {
    return "chill";
  }
  if (bpm < 100) {
    return "chill";
  }
  if (genre.includes("house") || genre.includes("dance")) {
    return bpm > 126 ? "club" : "lounge";
  }
  if (/\b(party|hype|turn\s?up|lit)\b/.test(keywordText) && bpm >= 118) {
    return "hype";
  }
  if (bpm >= 135) {
    return "hype";
  }
  return bpm >= 122 ? "club" : "lounge";
}

export function deriveEnergyLevel(input: {
  bpm?: number | null;
  genre?: string;
  keywords?: string[];
}): number {
  const bpm = input.bpm ?? 120;
  const genre = (input.genre ?? "").toLowerCase();
  const keywords = (input.keywords ?? []).join(" ").toLowerCase();
  // Maps BPM 85–155 to energy 0.12–0.98 linearly.
  // 85 BPM = low-energy R&B floor; 155 BPM = peak dance energy ceiling.
  let base = Math.max(0.12, Math.min((bpm - 85) / 70, 0.98));

  if (genre.includes("house") || genre.includes("club")) {
    base += 0.08;
  }
  if (genre.includes("r&b") || genre.includes("soul")) {
    base -= 0.14;
  }
  if (keywords.includes("remix") || keywords.includes("party")) {
    base += 0.05;
  }

  return Number(Math.max(0.12, Math.min(base, 0.99)).toFixed(3));
}
