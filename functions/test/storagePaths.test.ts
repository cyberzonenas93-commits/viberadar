import assert from "node:assert/strict";
import {
  ownedStoragePathFromUrl,
  storagePathFromFirebaseUrl,
} from "../src/lib/storagePaths";

const ownAudioUrl =
  "https://firebasestorage.googleapis.com/v0/b/demo/o/uploads%2Fuid-a%2Ftrack.mp3?alt=media&token=1";
const otherAudioUrl =
  "https://firebasestorage.googleapis.com/v0/b/demo/o/uploads%2Fuid-b%2Ftrack.mp3?alt=media&token=1";
const ownArtworkUrl =
  "https://firebasestorage.googleapis.com/v0/b/demo/o/artwork%2Fuid-a%2Fcover.jpg?alt=media";

assert.equal(
  storagePathFromFirebaseUrl(ownAudioUrl),
  "uploads/uid-a/track.mp3",
);
assert.equal(
  storagePathFromFirebaseUrl("uploads/uid-a/upload-1/audio_track.mp3"),
  "uploads/uid-a/upload-1/audio_track.mp3",
);
assert.equal(storagePathFromFirebaseUrl("https://example.com/no-object"), null);

assert.equal(
  ownedStoragePathFromUrl({
    url: ownAudioUrl,
    ownerUid: "uid-a",
    allowedRoots: ["uploads"],
  }),
  "uploads/uid-a/track.mp3",
);
assert.equal(
  ownedStoragePathFromUrl({
    url: "artwork/uid-a/upload-1/artwork.jpg",
    ownerUid: "uid-a",
    allowedRoots: ["artwork"],
  }),
  "artwork/uid-a/upload-1/artwork.jpg",
);
assert.equal(
  ownedStoragePathFromUrl({
    url: otherAudioUrl,
    ownerUid: "uid-a",
    allowedRoots: ["uploads"],
  }),
  null,
);
assert.equal(
  ownedStoragePathFromUrl({
    url: ownArtworkUrl,
    ownerUid: "uid-a",
    allowedRoots: ["uploads"],
  }),
  null,
);

console.log("storagePaths.test.ts: all assertions passed");
