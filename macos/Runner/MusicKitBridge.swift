import Cocoa
import FlutterMacOS
import MusicKit

@available(macOS 14.0, *)
class MusicKitBridge: NSObject {

    static let channel = "com.viberadar.musickit"

    static func register(with registrar: FlutterPluginRegistrar) {
        // no-op, registered via AppDelegate
    }

    static func setup(binaryMessenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: MusicKitBridge.channel, binaryMessenger: binaryMessenger)
        let bridge = MusicKitBridge()
        channel.setMethodCallHandler { call, result in
            Task { await bridge.handle(call: call, result: result) }
        }
    }

    // MARK: - Handle calls

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) async {
        switch call.method {
        case "getAuthorizationStatus":
            result(statusString(MusicAuthorization.currentStatus))

        case "requestAuthorization":
            let status = await MusicAuthorization.request()
            result(statusString(status))

        case "checkSubscription":
            do {
                let sub = try await MusicSubscription.current
                result(sub.canPlayCatalogContent)
            } catch {
                result(false)
            }

        case "search":
            guard let args = call.arguments as? [String: Any],
                  let query = args["query"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "query required", details: nil))
                return
            }
            let limit = args["limit"] as? Int ?? 25
            do {
                var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
                request.limit = limit
                let response = try await request.response()
                let songs = response.songs.map { song -> [String: Any?] in
                    [
                        "id":         song.id.rawValue,
                        "title":      song.title,
                        "artist":     song.artistName,
                        "album":      song.albumTitle ?? "",
                        "artwork":    song.artwork.map { art -> [String: Any] in
                            let url = art.url(width: 300, height: 300)?.absoluteString ?? ""
                            return ["url": url]
                        } as Any?,
                        "durationMs": song.duration.map { Int($0 * 1000) } as Any?,
                        "bpm":        nil as Any?,
                        "genre":      song.genreNames.first ?? "",
                        "releaseDate": song.releaseDate.map { ISO8601DateFormatter().string(from: $0) } as Any?,
                    ]
                }
                result(songs)
            } catch {
                result(FlutterError(code: "SEARCH_ERROR", message: error.localizedDescription, details: nil))
            }

        case "play":
            guard let args = call.arguments as? [String: Any],
                  let catalogId = args["catalogId"] as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "catalogId required", details: nil))
                return
            }
            do {
                try await playCatalogTrack(id: catalogId)
                result(nil)
            } catch {
                result(FlutterError(code: "PLAY_ERROR", message: error.localizedDescription, details: nil))
            }

        case "pause":
            ApplicationMusicPlayer.shared.pause()
            result(nil)

        case "resume":
            do {
                try await ApplicationMusicPlayer.shared.play()
                result(nil)
            } catch {
                result(FlutterError(code: "RESUME_ERROR", message: error.localizedDescription, details: nil))
            }

        case "stop":
            ApplicationMusicPlayer.shared.stop()
            result(nil)

        case "seek":
            guard let args = call.arguments as? [String: Any],
                  let position = args["position"] as? Double else {
                result(FlutterError(code: "BAD_ARGS", message: "position required", details: nil))
                return
            }
            ApplicationMusicPlayer.shared.playbackTime = position
            result(nil)

        case "setVolume":
            // ApplicationMusicPlayer does not expose a volume property on macOS
            result(nil)

        case "getPlaybackState":
            let player = ApplicationMusicPlayer.shared
            let pbStatus: String
            switch player.state.playbackStatus {
            case .playing:  pbStatus = "playing"
            case .paused:   pbStatus = "paused"
            case .stopped:  pbStatus = "stopped"
            case .interrupted: pbStatus = "paused"
            default:        pbStatus = "stopped"
            }
            result(["status": pbStatus, "currentTime": player.playbackTime])

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Helpers

    private func playCatalogTrack(id: String) async throws {
        var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(rawValue: id))
        request.limit = 1
        let response = try await request.response()
        guard let song = response.items.first else {
            throw NSError(domain: "MusicKit", code: 404, userInfo: [NSLocalizedDescriptionKey: "Track not found"])
        }
        let player = ApplicationMusicPlayer.shared
        player.queue = [song]
        try await player.play()
    }

    private func statusString(_ status: MusicAuthorization.Status) -> String {
        switch status {
        case .authorized:    return "authorized"
        case .notDetermined: return "notDetermined"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        @unknown default:    return "unknown"
        }
    }
}
