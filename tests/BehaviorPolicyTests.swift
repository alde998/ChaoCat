import Foundation
import CoreGraphics
@main struct Tests {
 static func main() {
  let primary=CGRect(x:0,y:25,width:1440,height:850)
  let left=CGRect(x:-1920,y:100,width:1920,height:1080)
  let above=CGRect(x:300,y:1200,width:1200,height:900)
  let screens=[primary,left,above]
  assert(BehaviorPolicy.movementArea(near:CGPoint(x:1100,y:500),screens:screens)==primary)
  assert(BehaviorPolicy.movementArea(near:CGPoint(x:-1500,y:300),screens:screens)==left)
  assert(BehaviorPolicy.movementArea(near:CGPoint(x:600,y:1500),screens:screens)==above)
  assert(BehaviorPolicy.movementArea(near:CGPoint(x:600,y:1100),screens:screens)==above,"A monitor gap must resolve to a real display")
  assert(BehaviorPolicy.movementArea(near:CGPoint(x:-2100,y:300),screens:screens)==left)
  assert(BehaviorPolicy.movementArea(near:.zero,screens:[]) == .zero)
  assert(BehaviorPolicy.randomMovementArea(screens:screens,random:{0})==primary)
  assert(BehaviorPolicy.randomMovementArea(screens:screens,random:{0.999999})==above)
  assert(BehaviorPolicy.randomMovementArea(screens:[],random:{0}) == .zero)
  assert(BehaviorPolicy.rest(roll:0.59) == .sit)
  assert(BehaviorPolicy.rest(roll:0.60) == .lick)
  assert(BehaviorPolicy.rest(roll:0.88) == .sleep)
  let choices=(0..<100).map {BehaviorPolicy.rest(roll:(Double($0)+0.5)/100)}
  assert(choices.filter{$0 == .sit}.count==60)
  assert(choices.filter{$0 == .lick}.count==28)
  assert(choices.filter{$0 == .sleep}.count==12)
  assert(BehaviorPolicy.canDive(distance:320,facing:.left,required:.left))
  assert(!BehaviorPolicy.canDive(distance:321,facing:.left,required:.left))
  assert(!BehaviorPolicy.canDive(distance:50,facing:.right,required:.left))
  let pile=CGPoint(x:500,y:400)
  let calibratedTakeoff=(1141.0-760)*0.228432+(800-348)*0.19036+18
  assert(abs(BehaviorPolicy.rubbishTakeoffDistance-calibratedTakeoff)<0.001)
  for facing in [PetFacing.left,.right] {
    let jump=BehaviorPolicy.rubbishTakeoff(heap:pile,facing:facing)
    let stage=BehaviorPolicy.rubbishStaging(heap:pile,facing:facing)
    assert(abs((pile.x-jump.x)*facing.sign-calibratedTakeoff)<0.001)
    assert(abs((jump.x-stage.x)*facing.sign-90)<0.001)
    assert(jump.y==pile.y && stage.y==pile.y)
  }
  let t=BehaviorPolicy.travel(distance:350,stride:170,cycle:1.2)
  assert(t.cycles==3 && abs(t.duration-3.6)<0.001)
  assert(BehaviorPolicy.poopRounds==3)
  assert(BehaviorPolicy.scaredRunRate==1)
  assert(BehaviorPolicy.scaredTransitionRate > 1)
  assert(BehaviorPolicy.scaredTravelDuration(distance:900)==0.5)
  var seed:UInt64=20261015
  func random()->CGFloat {
    seed=seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat(seed>>11)/CGFloat(UInt64(1)<<53)
  }
  // Sample actual consecutive legs, including edges on a left-hand monitor.
  let bounds=CGRect(x:-1810,y:28,width:1700,height:900)
  var point=CGPoint(x:bounds.midX,y:bounds.midY),previous:CGPoint?
  var horizontal=0,vertical=0,diagonal=0
  for _ in 0..<4000 {
    let next=BehaviorPolicy.scaredTarget(from:point,within:bounds,previous:previous,random:random)
    assert(next.x>=bounds.minX-0.001 && next.x<=bounds.maxX+0.001)
    assert(next.y>=bounds.minY-0.001 && next.y<=bounds.maxY+0.001)
    let vector=CGPoint(x:next.x-point.x,y:next.y-point.y),length=hypot(vector.x,vector.y)
    assert(length>=179.99,"No stalled edge hops")
    if let previous {
      assert((vector.x*previous.x+vector.y*previous.y)/(length*hypot(previous.x,previous.y))<0.941,"Change heading between sprints")
    }
    if abs(vector.y)<abs(vector.x)*0.364 {horizontal+=1}
    else if abs(vector.x)<abs(vector.y)*0.364 {vertical+=1}
    else {diagonal+=1}
    point=next;previous=vector
  }
  assert(horizontal>1000 && vertical>700 && diagonal>100 && diagonal<1400)
  print("Escape headings: horizontal \(horizontal), vertical \(vertical), diagonal \(diagonal) / 4000")
  var drag=PetDragGesture()
  drag.start(at:0);drag.record(delta:CGPoint(x:180,y:0),at:1)
  assert(!drag.requestsBury) // moving the cat gently only relocates it
  drag.start(at:1);drag.record(delta:CGPoint(x:2,y:0),at:1.001)
  assert(!drag.requestsBury) // a short input spike is not deliberate shaking
  drag.start(at:2);drag.record(delta:CGPoint(x:100,y:0),at:2.05)
  assert(drag.requestsBury)
  drag.start(at:3);assert(!drag.requestsBury) // the next click resets the gesture
  print("Behavior policy checks passed")
 }
}
