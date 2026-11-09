import SwiftUI

enum PlannerStyle {
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .init(white: 0.085, alpha: 1) : .init(red: 0.975, green: 0.970, blue: 0.950, alpha: 1) })
    static let moss = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.61, green: 0.83, blue: 0.60, alpha: 1) : UIColor(red: 0.14, green: 0.34, blue: 0.23, alpha: 1)
    })
    static let ochre = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.96, green: 0.72, blue: 0.46, alpha: 1) : UIColor(red: 0.56, green: 0.29, blue: 0.10, alpha: 1)
    })
    static let forest = Color(red: 0.10, green: 0.23, blue: 0.17)
    static let ink = Color.primary
    static let rule = Color(uiColor: .separator)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let blue = moss
    static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
}
