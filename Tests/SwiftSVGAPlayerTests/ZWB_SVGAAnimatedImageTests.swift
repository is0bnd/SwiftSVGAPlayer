import UIKit
import QuartzCore
import XCTest
@testable import SwiftSVGAPlayer

@MainActor
final class SVGAAnimatedImageTests: XCTestCase {
    func test_variableFrameDurations_preserveLastFrameDuration() throws {
        let resource = try XCTUnwrap(SVGAAnimatedImage(
            image: makeAnimatedImage(),
            frameDurations: [0.1, 0.3]
        ))

        XCTAssertEqual(resource.frames.count, 2)
        XCTAssertEqual(resource.duration, 0.4, accuracy: 0.000001)
        XCTAssertEqual(resource.keyTimes.map { $0.doubleValue }, [0, 0.25, 1])
    }

    func test_defaultTiming_usesUIImageDuration() throws {
        let resource = try XCTUnwrap(SVGAAnimatedImage(image: makeAnimatedImage()))

        XCTAssertEqual(resource.duration, 0.4, accuracy: 0.000001)
        XCTAssertEqual(resource.keyTimes.map { $0.doubleValue }, [0, 0.5, 1])
    }

    func test_invalidTiming_isRejected() {
        let image = makeAnimatedImage()
        XCTAssertNil(SVGAAnimatedImage(image: image, frameDurations: [0.1]))
        XCTAssertNil(SVGAAnimatedImage(image: image, frameDurations: [0, 0.1]))
        XCTAssertNil(SVGAAnimatedImage(image: image, frameDurations: [.infinity, 0.1]))
        XCTAssertNil(SVGAAnimatedImage(image: image, frameDurations: [.nan, 0.1]))
        XCTAssertNil(SVGAAnimatedImage(image: makeFrame(.red)))
    }

    func test_reapplyingResource_doesNotRestartContentsAnimation() throws {
        let resource = try XCTUnwrap(SVGAAnimatedImage(image: makeAnimatedImage()))
        let layer = SVGABitmapLayer()
        layer.setAnimatedImage(resource)
        let key = try XCTUnwrap(layer.animationKeys()?.first)
        let original = try XCTUnwrap(layer.animation(forKey: key) as? CAKeyframeAnimation)

        layer.setAnimatedImage(resource)
        let reapplied = try XCTUnwrap(layer.animation(forKey: key) as? CAKeyframeAnimation)

        XCTAssertEqual(reapplied.beginTime, original.beginTime)
        XCTAssertEqual(reapplied.calculationMode, .discrete)
        XCTAssertEqual(reapplied.values?.count, 2)
        XCTAssertEqual(reapplied.keyTimes?.count, 3)
    }

    func test_staticReplacementAndClear_removeContentsAnimation() throws {
        let resource = try XCTUnwrap(SVGAAnimatedImage(image: makeAnimatedImage()))
        let original = makeFrame(.green)
        let layer = SVGABitmapLayer()
        layer.configure(image: original)
        layer.setAnimatedImage(resource)

        layer.setDynamicImage(makeFrame(.blue))
        XCTAssertNil(layer.animationKeys())

        layer.setAnimatedImage(resource)
        layer.clearDynamic()
        XCTAssertNil(layer.animationKeys())
        XCTAssertTrue((layer.contents as AnyObject?) === original.cgImage)
    }

    func test_playbackClock_freezesOnPauseAndKeepsPositionOnResume() {
        let layer = SVGARenderLayer()
        XCTAssertEqual(layer.speed, 0)

        layer.setImageAnimationsPlaying(true)
        XCTAssertEqual(layer.speed, 1)
        layer.setImageAnimationsPlaying(false)
        let pausedTime = layer.timeOffset
        XCTAssertEqual(layer.speed, 0)
        XCTAssertEqual(layer.convertTime(CACurrentMediaTime(), from: nil), pausedTime)

        layer.setImageAnimationsPlaying(true)
        XCTAssertEqual(layer.speed, 1)
        XCTAssertEqual(layer.convertTime(CACurrentMediaTime(), from: nil), pausedTime, accuracy: 0.01)
    }

    func test_loadingAnotherVideoWhilePlaying_resumesAnimatedImageClock() async throws {
        let parser = AnimatedImageTestParser(videos: [makeVideo(side: 2), makeVideo(side: 3)])
        let player = SwiftSVGAPlayerView(frame: .zero, parser: parser)
        defer { player.clear() }
        var states = [SVGAPlaybackState]()
        player.onStateChange = { states.append($0) }

        try await player.load(.data(Data([0])))
        player.setImage(makeAnimatedImage(), forKey: "avatar")
        player.play(loop: .forever)
        let renderLayer = try XCTUnwrap(player.layer.sublayers?.first as? SVGARenderLayer)
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(renderLayer.speed, 1)

        try await player.load(.data(Data([1])))
        XCTAssertEqual(player.state, .ready)
        XCTAssertEqual(renderLayer.speed, 0)
        player.setImage(makeAnimatedImage(), forKey: "avatar")
        player.play(loop: .forever)

        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(renderLayer.speed, 1)
        XCTAssertEqual(states, [.loading, .ready, .playing, .loading, .ready, .playing])
        let spriteLayer = try XCTUnwrap(renderLayer.sublayers?.first as? SVGASpriteLayer)
        let bitmapLayer = try XCTUnwrap(spriteLayer.bitmapLayer)
        XCTAssertFalse(bitmapLayer.animationKeys()?.isEmpty ?? true)

        player.pause()
        XCTAssertEqual(player.state, .paused)
        XCTAssertEqual(renderLayer.speed, 0)
        player.resume()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(renderLayer.speed, 1)
    }

    func test_pauseInsidePlayingCallback_isPreservedByStateSynchronization() async throws {
        let parser = AnimatedImageTestParser(videos: [makeVideo(side: 2)])
        let player = SwiftSVGAPlayerView(frame: .zero, parser: parser)
        defer { player.clear() }
        player.onStateChange = { [weak player] state in
            if state == .playing {
                player?.pause()
            }
        }

        try await player.load(.data(Data([0])))
        player.setImage(makeAnimatedImage(), forKey: "avatar")
        player.play(loop: .forever)

        let renderLayer = try XCTUnwrap(player.layer.sublayers?.first as? SVGARenderLayer)
        XCTAssertEqual(player.state, .paused)
        XCTAssertEqual(renderLayer.speed, 0)
    }

    private func makeVideo(side: CGFloat) -> SVGAVideo {
        let frame = SVGAFrame(layout: SVGALayout(x: 0, y: 0, width: 2, height: 2))
        let sprite = SVGASprite(imageKey: "avatar", matteKey: nil, frames: [frame, frame])
        let image = SVGAImageResource(key: "avatar", image: makeFrame(.green))
        return SVGAVideo(
            size: CGSize(width: side, height: side),
            fps: 30,
            frames: 2,
            sprites: [sprite],
            images: ["avatar": image],
            audios: []
        )
    }

    private func makeAnimatedImage() -> UIImage {
        UIImage.animatedImage(with: [makeFrame(.red), makeFrame(.blue)], duration: 0.4)!
    }

    private func makeFrame(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}

private final class AnimatedImageTestParser: SVGAParsing {
    private var videos: [SVGAVideo]

    init(videos: [SVGAVideo]) {
        self.videos = videos
    }

    func parse(_ source: SVGASource) async throws -> SVGAVideo {
        guard !videos.isEmpty else { throw SVGAError.invalidData }
        return videos.removeFirst()
    }
}
