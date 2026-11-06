import Foundation

public struct ThermalPoint: Identifiable, Equatable, Sendable {
    public let column:Int
    public let row:Int
    public var id:String { "\(column)-\(row)" }
    public var position:Point2 { .init((Double(column)+0.5)/Double(ThermalGrid.columns),(Double(row)+0.5)/Double(ThermalGrid.rows)) }
    public init(column:Int,row:Int) { self.column=column;self.row=row }
    public func temperature(in sample:TemperatureSample?)->Double? {
        guard let sample,sample.isValid,let head=sample.head,let torso=sample.torso else { return nil }
        if self == ThermalGrid.overviewPoints[0] { return head }
        if self == ThermalGrid.overviewPoints[1] { return torso }
        let p=position
        let blend=min(1,max(0,(p.x-0.30)/0.10))
        let smooth=blend*blend*(3-2*blend)
        let headHot=exp(-pow((p.x-0.23)/0.14,2)-pow((p.y-0.47)/0.23,2))
        let torsoHot=exp(-pow((p.x-0.44)/0.17,2)-pow((p.y-0.55)/0.20,2))
        let cooling=0.35*(1-max(headHot,torsoHot))
        return min(max(head,torso),head*(1-smooth)+torso*smooth-cooling)
    }
}

public enum ThermalGrid {
    public static let columns=52
    public static let rows=30
    public static let points=(0..<rows).flatMap { row in (0..<columns).map { ThermalPoint(column:$0,row:row) } }
    // Region anchors in the supplied pose; live hardware will supply posture-aware contact maps.
    public static let overviewPoints=[ThermalPoint(column:11,row:13),ThermalPoint(column:22,row:16)]
    public static func trackingName(for point:ThermalPoint)->String {
        if point == overviewPoints[0] { return "머리 영역" }
        if point == overviewPoints[1] { return "몸통 영역" }
        return "선택 지점"
    }
    public static func nearest(to point:Point2,time:Double,reduced:Bool=false)->ThermalPoint {
        points.min { first,second in
            let a=ThermalProjection.position(first.position,time:time,reduced:reduced)
            let b=ThermalProjection.position(second.position,time:time,reduced:reduced)
            return hypot(a.x-point.x,(a.y-point.y)*9/16) < hypot(b.x-point.x,(b.y-point.y)*9/16)
        }!
    }
}

public enum ThermalProjection {
    public static let width=1000.0
    public static let height=562.5
    public static let imageWidth=1000.0
    public static let imageHeight=562.5
    public static func position(_ point:Point2,time:Double,reduced:Bool=false)->Point2 {
        BodyMotion.transform(point,time:time,reduced:reduced)
    }
}
