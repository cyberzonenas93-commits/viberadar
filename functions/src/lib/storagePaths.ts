export function storagePathFromFirebaseReference(
  value?: string,
): string | null {
  if (!value) return null;
  if (!value.startsWith("http://") && !value.startsWith("https://")) {
    return value.replace(/^\/+/, "");
  }

  const match = value.match(/\/o\/([^?]+)/);
  if (!match) return null;
  try {
    return decodeURIComponent(match[1]);
  } catch {
    return null;
  }
}

export const storagePathFromFirebaseUrl = storagePathFromFirebaseReference;

export function ownedStoragePathFromUrl(input: {
  url?: string;
  ownerUid: string;
  allowedRoots: readonly string[];
}): string | null {
  const path = storagePathFromFirebaseReference(input.url);
  if (!path) return null;

  const allowed = input.allowedRoots.some((root) =>
    path.startsWith(`${root}/${input.ownerUid}/`),
  );
  return allowed ? path : null;
}
