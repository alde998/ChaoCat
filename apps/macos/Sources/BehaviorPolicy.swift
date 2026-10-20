import Foundation
import CoreGraphics

enum PetFacing: String { case left, right
  var sign: CGFloat { self == .right ? 1 : -1 }
}
enum RestChoice: String { case sit, lick, sleep }
struct BehaviorPolicy {
  // Use an actual display, not the foreground app or the bounding rectangle
  // spanning multiple monitors (which can include gaps with no screen).
  static func movementArea(near point:CGPoint, screens:[CGRect])->CGRect {
    let areas=screens.filter{!$0.isNull && $0.width>0 && $0.height>0}
    if let area=areas.first(where:{$0.contains(point)}) {return area}
    func distance(to area:CGRect)->CGFloat {
      let dx=max(area.minX-point.x,0,point.x-area.maxX)
      let dy=max(area.minY-point.y,0,point.y-area.maxY)
      return hypot(dx,dy)
    }
    return areas.min(by:{distance(to:$0)<distance(to:$1)}) ?? .zero
  }
  static func randomMovementArea(screens:[CGRect], random:()->CGFloat = { CGFloat.random(in:0..<1) })->CGRect {
    let areas=screens.filter{!$0.isNull && $0.width>0 && $0.height>0}
    guard !areas.isEmpty else { return .zero }
    let index=min(areas.count-1,max(0,Int(random()*CGFloat(areas.count))))
    return areas[index]
  }
  static let rubbishRadius: CGFloat = 320
  // Calibrated jump and heap have separate scales/anchors. Leave 18 points
  // between the cat's nose and the heap edge at takeoff (layout audit).
  static let rubbishTakeoffDistance: CGFloat = (1141 - 760) * 0.228432 + (800 - 348) * 0.19036 + 18
  static let rubbishRunway: CGFloat = 90
  static func rubbishTakeoff(heap: CGPoint, facing: PetFacing) -> CGPoint {
    CGPoint(x: heap.x - rubbishTakeoffDistance * facing.sign, y: heap.y)
  }
  static func rubbishStaging(heap: CGPoint, facing: PetFacing) -> CGPoint {
    CGPoint(x: heap.x - (rubbishTakeoffDistance + rubbishRunway) * facing.sign, y: heap.y)
  }
  static let catchRadius: CGFloat = 150
  static let dragLiftRate: Double = 1.6
  static let chaseSpeed: CGFloat = 104
  static let pounceApproachRadius: CGFloat = 45
  static let typingBugChance = 0.12
  static let ambientBugChance = 0.03
  static let typingBugInterval: TimeInterval = 3
  static let ambientBugInterval: TimeInterval = 8
  static let bugCooldown: TimeInterval = 25
  static let bugFlightSpeed: CGFloat = 52
  static let bugEscapeSpeed: CGFloat = 78
  // A quick, deliberate drag is the legacy gesture for starting cleanup.
  // Keep this threshold in policy so the input gesture and tests share it.
  static let fastDragSpeed: CGFloat = 900
  // Movement has its own clock; the GIF keeps its authored frame cadence.
  static let scaredRunRate: Double = 1.0
  static let scaredTransitionRate: Double = 2.2
  static let scaredRunSpeed: CGFloat = 1800
  static let scatterInterval: TimeInterval = 0.16
  static let scatteredPoopCount = 12
  static func scaredTravelDuration(distance:CGFloat)->TimeInterval {
    max(0.01,Double(distance/scaredRunSpeed))
  }
  static func scaredTarget(from origin:CGPoint, within bounds:CGRect, previous:CGPoint?,
                           random:()->CGFloat = { CGFloat.random(in:0..<1) })->CGPoint {
    let start=CGPoint(x:min(bounds.maxX,max(bounds.minX,origin.x)),y:min(bounds.maxY,max(bounds.minY,origin.y)))
    let minimum=min(180,max(bounds.width,bounds.height)*0.25)
    for _ in 0..<48 {
      // Choose a heading, not unrelated x/y destinations. Most sprints are
      // near horizontal/vertical; the remainder can take any angle.
      let choice=random(),jitter=(random()-0.5)*CGFloat.pi/9
      let angle:CGFloat
      if choice<0.4 { angle=(random()<0.5 ? 0 : .pi)+jitter }
      else if choice<0.7 { angle=(random()<0.5 ? .pi/2 : -.pi/2)+jitter }
      else { angle=random()*2 * .pi }
      let dx=cos(angle),dy=sin(angle)
      if let previous {
        let length=hypot(previous.x,previous.y)
        if length>0 && (dx*previous.x+dy*previous.y)/length>0.94 {continue}
      }
      // Shorten the ray at the edge instead of clamping each coordinate,
      // which biases trajectories toward corners and creates tiny hops.
      let roomX=abs(dx)<0.00001 ? CGFloat.infinity : (dx>0 ? bounds.maxX-start.x : start.x-bounds.minX)/abs(dx)
      let roomY=abs(dy)<0.00001 ? CGFloat.infinity : (dy>0 ? bounds.maxY-start.y : start.y-bounds.minY)/abs(dy)
      let length=min(300+random()*650,min(roomX,roomY))
      if length<minimum {continue}
      return CGPoint(x:start.x+dx*length,y:start.y+dy*length)
    }
    // Degenerate bounds or repeated rejected samples still make progress.
    return CGPoint(x:start.x<bounds.midX ? bounds.maxX:bounds.minX,
                   y:start.y<bounds.midY ? bounds.maxY:bounds.minY)
  }
  static let bugLifetime: TimeInterval = 16
  static let poopRounds = 3
  // Per rest entry: seated tail motion 60%, seated licking 28%, sleep 12%.
  static func rest(roll: Double) -> RestChoice { roll < 0.60 ? .sit : roll < 0.88 ? .lick : .sleep }
  static func canDive(distance: CGFloat, facing: PetFacing, required: PetFacing) -> Bool {
    distance <= rubbishRadius && facing == required
  }
  static func travel(distance: CGFloat, stride: CGFloat, cycle: TimeInterval) -> (cycles: Int, duration: TimeInterval) {
    let cycles = max(1, Int(ceil(max(0, distance) / max(1, stride))))
    return (cycles, Double(cycles) * max(0.01, cycle))
  }
  static func dragTriggersBury(maxSpeed: CGFloat, distance: CGFloat) -> Bool {
    distance >= 24 && maxSpeed >= fastDragSpeed
  }
}

// Sample event timestamps, not rendering time: decoding a GIF must not change
// whether a physical gesture counts as fast. Each mouse-down starts a new trace.
struct PetDragGesture {
  private var lastTime: TimeInterval = 0
  private(set) var maxSpeed: CGFloat = 0
  private(set) var distance: CGFloat = 0
  mutating func start(at time: TimeInterval) {
    lastTime=time;maxSpeed=0;distance=0
  }
  mutating func record(delta: CGPoint, at time: TimeInterval) {
    let step=hypot(delta.x,delta.y)
    distance += step
    if time > lastTime { maxSpeed=max(maxSpeed,step/CGFloat(max(0.008,time-lastTime))) }
    lastTime=max(lastTime,time)
  }
  var requestsBury: Bool { BehaviorPolicy.dragTriggersBury(maxSpeed:maxSpeed,distance:distance) }
}
