import UIKit

final class JonworkPastelBackgroundView: UIView {
    static let accent = UIColor(red: 0.039, green: 0.482, blue: 1.0, alpha: 1.0)
    static let surface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.059, blue: 0.067, alpha: 1)
            : UIColor(red: 0.973, green: 0.976, blue: 0.980, alpha: 1)
    }

    private let blueGlow = CAGradientLayer()
    private let fadeLayer = CAGradientLayer()
    private let intensity: CGFloat

    init(intensity: CGFloat = 1) {
        self.intensity = intensity
        super.init(frame: .zero)
        backgroundColor = Self.surface
        [blueGlow].forEach {
            $0.type = .radial
            $0.locations = [0, 1]
            layer.addSublayer($0)
        }
        layer.addSublayer(fadeLayer)
        refreshColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: JonworkPastelBackgroundView, _) in
            view.refreshColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        [blueGlow, fadeLayer].forEach { $0.frame = bounds }
        blueGlow.startPoint = CGPoint(x: 0.22, y: 0.02)
        blueGlow.endPoint = CGPoint(x: 0.84, y: 0.72)
    }

    private func refreshColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        backgroundColor = Self.surface
        let alpha = (isDark ? 0.12 : 0.20) * intensity
        blueGlow.colors = [
            UIColor(red: 0.32, green: 0.64, blue: 1, alpha: alpha).cgColor,
            UIColor(red: 0.32, green: 0.64, blue: 1, alpha: 0).cgColor,
        ]
        fadeLayer.colors = [
            Self.surface.withAlphaComponent(0).cgColor,
            Self.surface.withAlphaComponent(isDark ? 0.72 : 0.58).cgColor,
            Self.surface.cgColor,
        ]
        fadeLayer.locations = [0, 0.52, 1]
        fadeLayer.startPoint = CGPoint(x: 0.5, y: 0)
        fadeLayer.endPoint = CGPoint(x: 0.5, y: 1)
    }
}
