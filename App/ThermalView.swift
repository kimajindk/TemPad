import SwiftUI
import SpriteKit
import TemPadCore

final class ThermalScene: SKScene {
    private let baby = SKSpriteNode(texture: SKTexture(imageNamed: "ThermalBaby"))
    private let columns = 16, rows = 10
    private var lastDraw: TimeInterval = 0
    private var heat: SKShader?
    var motionTime: Double = 0
    var head: Double = 36.8
    var torso: Double = 37.1
    var reduced = false

    override init(size: CGSize) { super.init(size:size); setup() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .clear
        scaleMode = .aspectFit
        baby.size = CGSize(width:ThermalProjection.imageWidth,height:ThermalProjection.imageHeight)
        baby.position = CGPoint(x:size.width/2,y:size.height/2)
        baby.zRotation = 0
        baby.texture?.filteringMode = .linear
        baby.subdivisionLevels = 0
        addChild(baby)
        let shader = SKShader(source:"""
        void main() {
            vec4 c = texture2D(u_texture, v_tex_coord);
            float alpha = c.a;
            vec3 rgb = alpha > 0.001 ? c.rgb / alpha : c.rgb;
            float delta = mix(u_head, u_torso, smoothstep(0.34, 0.48, v_tex_coord.x));
            rgb.g = clamp(rgb.g - delta * 0.22, 0.04, 1.0);
            rgb.b = clamp(rgb.b - delta * 0.12, 0.02, 1.0);
            if (delta < -0.8) rgb = mix(rgb, vec3(0.35,0.78,1.0), min(0.85,-delta*0.35));
            gl_FragColor = vec4(rgb * alpha, alpha);
        }
        """)
        shader.uniforms = [SKUniform(name:"u_head",float:0),SKUniform(name:"u_torso",float:0)]
        baby.shader = shader
        heat = shader
    }

    override func update(_ currentTime: TimeInterval) {
        guard currentTime-lastDraw >= 1.0/30 else { return }
        lastDraw = currentTime
        var source:[SIMD2<Float>] = [], destination:[SIMD2<Float>] = []
        for y in 0...rows {
            for x in 0...columns {
                let nx=Double(x)/Double(columns),ny=Double(y)/Double(rows)
                source.append(SIMD2(Float(nx),Float(ny)))
                let p=BodyMotion.transform(.init(nx,1-ny),time:motionTime,reduced:reduced)
                destination.append(SIMD2(Float(p.x),Float(1-p.y)))
            }
        }
        baby.warpGeometry = SKWarpGeometryGrid(columns:columns,rows:rows,sourcePositions:source,destinationPositions:destination)
        heat?.uniformNamed("u_head")?.floatValue = Float(head-36.8)
        heat?.uniformNamed("u_torso")?.floatValue = Float(torso-37.1)
    }
}

struct ThermalBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.cream
                RadialGradient(colors:[Color(red:0.65,green:0.83,blue:0.91),Color(red:0.82,green:0.9,blue:0.92),Palette.cream],center:.center,startRadius:0,endRadius:max(geometry.size.width,geometry.size.height)*0.68)

            }
        }
        .accessibilityHidden(true)
    }
}

enum ThermalMask {
    static let covered:Set<String> = {
        guard let source=UIImage(named:"ThermalBaby") else { return Set(ThermalGrid.points.map(\.id)) }
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=false;format.preferredRange = .standard
        let size=CGSize(width:ThermalGrid.columns,height:ThermalGrid.rows)
        let rendered=UIGraphicsImageRenderer(size:size,format:format).image { _ in source.draw(in:CGRect(origin:.zero,size:size)) }
        guard let image=rendered.cgImage,let data=image.dataProvider?.data,let bytes=CFDataGetBytePtr(data),image.bitsPerPixel == 32 else { return Set(ThermalGrid.points.map(\.id)) }
        let little=image.bitmapInfo.contains(.byteOrder32Little)
        let first=image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first
        let alphaIndex=first ? (little ? 3:0):(little ? 0:3)
        return Set(ThermalGrid.points.filter { point in bytes[point.row*image.bytesPerRow+point.column*4+alphaIndex] > 64 }.map(\.id))
    }()
}

struct ThermalView: View {
    var store:MonitorStore
    @Binding var selectedPoint:ThermalPoint?
    var showLegend=true
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var scene=ThermalScene(size:CGSize(width:ThermalProjection.width,height:ThermalProjection.height))

    var body:some View {
        GeometryReader { geometry in
            let width=min(geometry.size.width,geometry.size.height*16/9)
            let height=width*9/16
            TimelineView(.animation(minimumInterval:1.0/30,paused:!store.isActive || !store.motionFresh)) { timeline in
                let time=store.motionFresh ? max(0,timeline.date.timeIntervalSince(store.motionStartedAt)):store.poseTime
                ZStack {
                    SpriteView(scene:scene,preferredFramesPerSecond:30,options:[.allowsTransparency]).accessibilityHidden(true)
                    Canvas { context,size in
                        for point in ThermalGrid.points {
                            let p=ThermalProjection.position(point.position,time:time,reduced:reduced)
                            let covered=ThermalMask.covered.contains(point.id)
                            context.fill(Path(ellipseIn:CGRect(x:p.x*size.width-0.6,y:p.y*size.height-0.6,width:1.2,height:1.2)),with:.color(.white.opacity(covered ? 0.95:0.6)))
                        }
                    }.allowsHitTesting(false).accessibilityHidden(true)
                    ForEach(selectedPoint.map{[$0]} ?? ThermalGrid.overviewPoints) { point in
                        let p=ThermalProjection.position(point.position,time:time,reduced:reduced)
                        let x=p.x*width,y=p.y*height
                        let isSelected=selectedPoint != nil
                        let tracking=store.temperatureFresh && store.motionFresh && store.isActive
                        let age=max(0,timeline.date.timeIntervalSince(store.latest?.date ?? timeline.date))
                        let pulse=tracking && !reduced ? max(0,1-age/1.2):0
                        let defaultLabelX=(point == ThermalGrid.overviewPoints[0] ? width*0.21:width*0.52)+(p.x-point.position.x)*width
                        let labelX=min(max(isSelected ? x:defaultLabelX,56),width-56)
                        let labelY=isSelected ? (y < 72 ? y+56:y-48):max(32,y-64)
                        Circle().fill(tracking ? Palette.wine.opacity(0.75+pulse*0.25):Palette.muted)
                            .frame(width:8,height:8)
                            .overlay(Circle().strokeBorder(.white,lineWidth:1.5))
                            .position(x:x,y:y).allowsHitTesting(false)
                        VStack(alignment:.leading,spacing:8) {
                            HStack(spacing:8) {
                                Text(isSelected ? "선택 지점":(point == ThermalGrid.overviewPoints[0] ? "머리":"몸통"))
                                    .font(.system(size:10,weight:.semibold))
                                if !isSelected {
                                    Circle()
                                        .fill(tracking ? Color(red:0.22,green:0.70,blue:0.43):Palette.muted.opacity(0.4))
                                        .frame(width:8,height:8)
                                        .shadow(color:tracking ? Color.green.opacity(0.35):.clear,radius:3)
                                        .accessibilityLabel(tracking ? "추적 중":"추적 대기")
                                }
                            }
                            Text(temperatureString(point.temperature(in:store.temperatureFresh ? store.latest:nil))+"°C")
                                .font(.system(size:18,weight:.medium,design:.rounded)).monospacedDigit()
                        }
                        .padding(8).background(.white.opacity(0.9),in:RoundedRectangle(cornerRadius:8))
                        .position(x:labelX,y:labelY)
                        .allowsHitTesting(false).accessibilityElement(children:.combine)
                        .accessibilityIdentifier("pointTemperature-"+point.id)
                    }
                }
                .frame(width:width,height:height)
                .frame(width:geometry.size.width,height:geometry.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged { value in
                    guard let point=sampledPoint(at:value.location,in:geometry.size,time:time),selectedPoint != point else { return }
                    selectedPoint=point
                }.onEnded { value in
                    if sampledPoint(at:value.location,in:geometry.size,time:time) == nil {
                        withAnimation(.easeInOut(duration:0.2)) { selectedPoint=nil }
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                })
                .onAppear { updateScene(time) }
                .onChange(of:timeline.date) { _,_ in updateScene(time) }
            }
        }
        .overlay(alignment:.topLeading) {
            if showLegend {
                LinearGradient(colors:[.cyan.opacity(0.5),.yellow,.orange,Color(red:1,green:0.28,blue:0.28)],startPoint:.leading,endPoint:.trailing)
                    .frame(width:64,height:4).clipShape(Capsule()).padding(16).allowsHitTesting(false)
            }
        }
        .overlay(alignment:.bottom) {
            if !store.motionFresh {
                Text("마지막 모습 · 움직임 정보 확인 중")
                    .font(.caption).padding(16).background(.regularMaterial,in:Capsule()).padding(16)
            }
        }
        .accessibilityElement(children:.contain)
        .accessibilityLabel(store.temperatureFresh ? "아기 온도 모니터링. 격자 지점을 눌러 온도를 확인하세요":"아기 온도 모니터링. 새로운 온도 정보를 기다리고 있어요")
        .accessibilityIdentifier("thermalView")
        .accessibilityAction(named:"중앙 지점 선택") { selectedPoint=ThermalGrid.overviewPoints[1] }
        .accessibilityAction(named:"기본 추적 지점으로 돌아가기") { selectedPoint=nil }
    }
    private func updateScene(_ time:Double) {
        scene.motionTime=time;scene.head=store.latest?.head ?? 36.8;scene.torso=store.latest?.torso ?? 37.1;scene.reduced=reduced
    }
    private func sampledPoint(at location:CGPoint,in size:CGSize,time:Double)->ThermalPoint? {
        let width=min(size.width,size.height*16/9)
        let height=width*9/16
        guard width>0,height>0 else { return nil }
        let normalized=Point2((location.x-(size.width-width)/2)/width,(location.y-(size.height-height)/2)/height)
        guard (0...1).contains(normalized.x),(0...1).contains(normalized.y) else { return nil }
        let point=ThermalGrid.nearest(to:normalized,time:time,reduced:reduced)
        return ThermalMask.covered.contains(point.id) ? point:nil
    }
}
