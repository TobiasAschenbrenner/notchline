import SwiftUI

struct NotchContour: Shape {
    var shoulder: CGFloat
    var corner: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(shoulder, corner) }
        set { shoulder = newValue.first; corner = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let shoulderInset = min(shoulder, height * 0.34)
        let cornerRadius = min(corner, (height - shoulderInset) * 0.7)
        let rightEdge = width - shoulderInset
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addCurve(to: CGPoint(x: rightEdge, y: shoulderInset),
                      control1: CGPoint(x: width - shoulderInset * 0.58, y: 0), control2: CGPoint(x: rightEdge, y: shoulderInset * 0.42))
        path.addLine(to: CGPoint(x: rightEdge, y: height - cornerRadius))
        path.addCurve(to: CGPoint(x: rightEdge - cornerRadius, y: height),
                      control1: CGPoint(x: rightEdge, y: height - cornerRadius * 0.33), control2: CGPoint(x: rightEdge - cornerRadius * 0.33, y: height))
        path.addLine(to: CGPoint(x: shoulderInset + cornerRadius, y: height))
        path.addCurve(to: CGPoint(x: shoulderInset, y: height - cornerRadius),
                      control1: CGPoint(x: shoulderInset + cornerRadius * 0.33, y: height), control2: CGPoint(x: shoulderInset, y: height - cornerRadius * 0.33))
        path.addLine(to: CGPoint(x: shoulderInset, y: shoulderInset))
        path.addCurve(to: .zero, control1: CGPoint(x: shoulderInset, y: shoulderInset * 0.42), control2: CGPoint(x: shoulderInset * 0.58, y: 0))
        path.closeSubpath()
        return path
    }
}
