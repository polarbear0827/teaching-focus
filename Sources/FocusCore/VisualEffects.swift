import Foundation
import CoreGraphics

public enum ParticleKind: Int, CaseIterable { case dots, sparks, stars }
public struct ParticleSample {
    public let point: CGPoint
    public let angle: Double
    public let size: Double
    public let opacity: Double
}
public struct ParticleBurst {
    public let origin: CGPoint
    public let born: Double
    public let kind: ParticleKind
    public let intensity: Int
    public static let lifetime = 0.6
    public init(origin: CGPoint, born: Double, kind: ParticleKind, intensity: Int) {
        self.origin=origin; self.born=born; self.kind=kind; self.intensity=min(5,max(1,intensity))
    }
    public func samples(at time: Double) -> [ParticleSample] {
        let age=time-born
        guard age >= 0 && age < Self.lifetime else { return [] }
        let progress=age/Self.lifetime
        let count=[6,10,16,24,32][intensity-1]
        let reach=[24.0,32,42,54,68][intensity-1]
        return (0..<count).map { index in
            let angle=Double(index)*2*Double.pi/Double(count)+Double(intensity)*0.17
            let distance=reach*(1-pow(1-progress,2))*(0.65+Double(index%4)*0.1)
            return ParticleSample(point:CGPoint(x:origin.x+cos(angle)*distance,y:origin.y+sin(angle)*distance),angle:angle,size:2+Double(index%3)*0.6,opacity:pow(1-progress,2))
        }
    }
}
public struct ParticleBuffer {
    public private(set) var bursts: [ParticleBurst] = []
    public init() {}
    public mutating func add(_ burst: ParticleBurst, reducedMotion: Bool = false) {
        guard !reducedMotion else { return }
        expire(at:burst.born)
        bursts.append(burst)
        if bursts.count > 8 { bursts.removeFirst(bursts.count-8) }
    }
    public mutating func expire(at time: Double) { bursts.removeAll { time-$0.born >= ParticleBurst.lifetime } }
    public mutating func clear() { bursts.removeAll() }
    public mutating func removeOldest() { if !bursts.isEmpty { bursts.removeFirst() } }
}

public enum FloatingLayout {
    public static let ballSize: CGFloat = 44
    public static let margin: CGFloat = 12
    public static func ball(in screen: CGRect, right: Bool, fraction: Double) -> CGRect {
        let minX=screen.minX+margin, maxX=max(minX,screen.maxX-margin-ballSize)
        let travel=max(0,screen.height-2*margin-ballSize)
        let fraction=fraction.isFinite ? min(1,max(0,fraction)) : 0.5
        return CGRect(x:right ? maxX:minX,y:screen.minY+margin+travel*fraction,width:ballSize,height:ballSize)
    }
    public static func clamped(origin: CGPoint, in screen: CGRect) -> CGRect {
        CGRect(x:min(max(origin.x,screen.minX+margin),max(screen.minX+margin,screen.maxX-margin-ballSize)),
               y:min(max(origin.y,screen.minY+margin),max(screen.minY+margin,screen.maxY-margin-ballSize)),width:ballSize,height:ballSize)
    }
    public static func snapped(_ frame: CGRect, in screen: CGRect) -> (frame: CGRect, right: Bool, fraction: Double) {
        let right=frame.midX >= screen.midX
        let travel=max(1,screen.height-2*margin-ballSize)
        let fraction=Double(min(1,max(0,(frame.minY-screen.minY-margin)/travel)))
        return (ball(in:screen,right:right,fraction:fraction),right,fraction)
    }
    public static func panel(beside ball: CGRect, in screen: CGRect, height: CGFloat = 320) -> CGRect {
        let width=min(320,max(1,screen.width-2*margin))
        let height=min(height,max(1,screen.height-2*margin))
        let desiredX=ball.midX >= screen.midX ? ball.minX-10-width:ball.maxX+10
        return CGRect(x:min(max(desiredX,screen.minX+margin),screen.maxX-margin-width),
                      y:min(max(ball.midY-height/2,screen.minY+margin),screen.maxY-margin-height),width:width,height:height)
    }
    public static func isDrag(from: CGPoint, to: CGPoint) -> Bool { hypot(to.x-from.x,to.y-from.y) >= 4 }
}
public struct OutsideClickGate {
    private var held: Set<Int> = []
    public init() {}
    public mutating func down(button: Int, dismissing: Bool) -> Bool { if dismissing { held.insert(button) }; return held.contains(button) }
    public func dragging(button: Int) -> Bool { held.contains(button) }
    public mutating func up(button: Int) -> Bool { held.remove(button) != nil }
    public mutating func reset() { held.removeAll() }
}
