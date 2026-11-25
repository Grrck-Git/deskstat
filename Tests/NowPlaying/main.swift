import AppKit

func decode(_ json: String) throws -> SystemNowPlaying? {
    try JSONDecoder().decode(SystemNowPlaying?.self, from: Data(json.utf8))
}
let playing = try decode(#"{"title":"A track","artist":"An artist","playing":true,"elapsedTimeNow":50,"elapsedTime":1,"duration":100}"#)!
let display = playing.display(source: "Safari")!
precondition(display.contains("An artist · Safari · Playing") && display.contains("50%"))
let paused = try decode(#"{"title":"A podcast","playing":false}"#)!
precondition(paused.display(source: "Spotify") == "A podcast\nSpotify · Paused")
let empty = try decode("null")
precondition(empty == nil)
let untitled = try decode(#"{"title":" \n "}"#)!
precondition(untitled.display(source: "Music") == nil)
let live = try decode(#"{"title":"Radio","duration":0,"playing":true}"#)!
precondition(live.display(source: "Safari") == "Radio\nSafari · Playing")
let clamped = try decode(#"{"title":"End","elapsedTime":110,"duration":100,"playing":false}"#)!
precondition(clamped.display(source: "Music")!.contains("100%"))
let multiline = try decode(#"{"title":"Line 1\nLine 2","artist":"Name\nName","playing":true}"#)!
precondition(multiline.display(source: "Safari")!.hasPrefix("Line 1 Line 2\nName Name"))
print("PASS playing, paused, absent metadata, missing artist/progress, live streams, timing and multiline text")
