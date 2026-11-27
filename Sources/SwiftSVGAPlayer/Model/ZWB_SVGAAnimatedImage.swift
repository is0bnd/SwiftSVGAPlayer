import UIKit

/// 已展开的动图帧及其播放时序，不负责图片下载或格式解码。
public final class SVGAAnimatedImage {
    let image: UIImage
    let frames: [CGImage]
    let duration: TimeInterval
    let keyTimes: [NSNumber]

    /// 不传 frameDurations 时，按 UIImage 的总时长均分各帧。
    public init?(image: UIImage, frameDurations: [TimeInterval]? = nil) {
        guard let images = image.images, images.count > 1 else { return nil }
        let frames = images.compactMap { $0.cgImage }
        guard frames.count == images.count else { return nil }

        let durations = frameDurations ?? Array(
            repeating: image.duration / Double(frames.count),
            count: frames.count
        )
        guard durations.count == frames.count,
              durations.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let duration = durations.reduce(0, +)
        guard duration.isFinite, duration > 0 else { return nil }

        var elapsed: TimeInterval = 0
        var keyTimes = [NSNumber(value: 0.0)]
        for frameDuration in durations {
            elapsed += frameDuration
            keyTimes.append(NSNumber(value: elapsed / duration))
        }
        // discrete 模式需要比帧数多一个结束时间点。
        keyTimes[keyTimes.count - 1] = NSNumber(value: 1.0)

        self.image = image
        self.frames = frames
        self.duration = duration
        self.keyTimes = keyTimes
    }
}
